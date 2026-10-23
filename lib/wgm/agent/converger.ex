defmodule WGM.Agent.Converger do
  @moduledoc """
  Конвейер converge инстанса на агенте.

  Поток:
    1. валидация действия и предусловий (в т.ч. «нет пиров» для :absent);
    2. построение превью-диффа (current config ↔ desired config);
    3. определение фактического состояния интерфейса (:up/:down/:absent);
    4. для деструктивных операций — требование явного подтверждения;
    5. бэкап текущего конфига с ротацией;
    6. атомарная запись/удаление конфига;
    7. приведение ядра к целевому состоянию:
       - :up — создать интерфейс (wg-quick up) или syncconf со strip;
       - :down — wg-quick down, если интерфейс есть;
       - :restart — down → up;
       - :absent — down → удалить конфиг;
    8. проверка результата через `show dump`;
    9. откат из бэкапа при расхождении.

  Приватный ключ сервера читается из локального `key_store` агента.
  """

  alias WGM.{ConfigGenerator, Instance, Parser}

  @type action :: :up | :down | :restart | :absent
  @type interface_state :: :up | :down | :absent
  @type result :: map()

  @doc """
  Приводит фактическое состояние инстанса на узле к желаемому.

  Опции:
    - `:action` — `:up` (по умолчанию), `:down`, `:restart`, `:absent`;
    - `:confirm` — `true`/`false`, требуется для деструктивных действий;
    - `:dry_run` — `true`/`false`, только превью-дифф без изменений.
  """
  @spec converge(map(), Instance.t(), [WGM.Peer.t()], keyword()) ::
          {:ok, result()} | {:error, String.t()}
  def converge(state, instance, peers, opts \\ []) do
    action = opts[:action] || :up
    confirm = Keyword.get(opts, :confirm, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    with :ok <- validate_action(action),
         :ok <- validate_preconditions(action, instance, peers),
         {:ok, current_config} <- read_current_config(state, instance),
         {:ok, desired_config} <-
           build_desired_config(state, instance, peers, action, current_config),
         interface_state = fetch_interface_state(state, instance),
         diff = compute_diff(current_config, desired_config),
         changed? = changed?(action, current_config, diff, interface_state),
         :ok <- maybe_require_confirmation(action, confirm, dry_run, changed?) do
      result = %{
        action: action,
        dry_run: dry_run,
        diff: diff,
        changed: changed?
      }

      if dry_run or not changed? do
        {:ok, result}
      else
        do_apply(
          state,
          instance,
          peers,
          action,
          current_config,
          desired_config,
          interface_state,
          result
        )
      end
    end
  end

  defp validate_action(action) when action in [:up, :down, :restart, :absent], do: :ok
  defp validate_action(action), do: {:error, "Unknown converge action: #{inspect(action)}"}

  defp validate_preconditions(:absent, _instance, [_ | _]) do
    {:error, "Instance has peers"}
  end

  defp validate_preconditions(_action, _instance, _peers), do: :ok

  defp build_desired_config(_state, _instance, _peers, :absent, _current), do: {:ok, nil}
  defp build_desired_config(_state, _instance, _peers, :down, current), do: {:ok, current}

  defp build_desired_config(state, instance, peers, _action, _current) do
    with {:ok, private_key} <- fetch_private_key(state, instance),
         {:ok, config} <- ConfigGenerator.generate_server_config(instance, peers, private_key) do
      {:ok, config}
    end
  end

  defp fetch_private_key(state, instance) do
    case state.key_store.read_private_key(instance.protocol, instance.id) do
      {:ok, key} -> {:ok, key}
      {:error, :enoent} -> {:error, "Private key not found for instance #{instance.id}"}
      {:error, reason} -> {:error, "Failed to read private key: #{inspect(reason)}"}
    end
  end

  defp read_current_config(state, instance) do
    case state.config_store.read_config(instance.protocol, instance.name) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, "Failed to read current config: #{inspect(reason)}"}
    end
  end

  defp fetch_interface_state(state, instance) do
    case state.adapter.interface_state(instance.name) do
      {:ok, :up} -> :up
      {:ok, :down} -> :down
      _other -> :absent
    end
  end

  defp compute_diff(nil, nil), do: []

  defp compute_diff(nil, desired) do
    desired
    |> lines()
    |> Enum.map(&"+ #{&1}")
  end

  defp compute_diff(current, nil) do
    current
    |> lines()
    |> Enum.map(&"- #{&1}")
  end

  defp compute_diff(current, desired) do
    current_lines = lines(current)
    desired_lines = lines(desired)

    List.myers_difference(current_lines, desired_lines)
    |> Enum.flat_map(fn
      {:eq, lines} -> Enum.map(lines, &"  #{&1}")
      {:del, lines} -> Enum.map(lines, &"- #{&1}")
      {:ins, lines} -> Enum.map(lines, &"+ #{&1}")
    end)
  end

  defp lines(config) do
    config
    |> String.split("\n", trim: false)
    |> drop_trailing_empty()
  end

  defp drop_trailing_empty(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp changed?(:up, _current_config, _diff, :absent), do: true
  defp changed?(:up, _current_config, _diff, :down), do: true
  defp changed?(:up, _current_config, diff, :up), do: diff_non_empty?(diff)
  defp changed?(:down, _current_config, _diff, :up), do: true
  defp changed?(:down, _current_config, _diff, _), do: false
  defp changed?(:restart, _current_config, _diff, _), do: true
  defp changed?(:absent, nil, _diff, :absent), do: false
  defp changed?(:absent, _current_config, _diff, _), do: true

  defp diff_non_empty?(diff) do
    Enum.any?(diff, fn line ->
      String.starts_with?(line, "+") or String.starts_with?(line, "-")
    end)
  end

  defp maybe_require_confirmation(:up, _confirm, false, _changed?), do: :ok
  defp maybe_require_confirmation(_action, true, false, _changed?), do: :ok
  defp maybe_require_confirmation(_action, _confirm, true, _changed?), do: :ok

  defp maybe_require_confirmation(action, false, false, true)
       when action in [:down, :restart, :absent] do
    {:error, "Destructive action #{action} requires confirmation"}
  end

  defp maybe_require_confirmation(_action, false, false, false), do: :ok

  defp do_apply(
         state,
         instance,
         peers,
         :absent,
         current_config,
         _desired_config,
         interface_state,
         result
       ) do
    # Для :absent сначала опускаем интерфейс по существующему конфигу,
    # и только потом удаляем/бэкапим файл (см. ревью wgm-65b6323).
    with :ok <- apply_to_kernel(state, instance, :absent, interface_state),
         :ok <- backup(state, instance, :absent, current_config),
         :ok <- write_or_delete_config(state, instance, :absent, nil),
         :ok <- verify(state, instance, peers, :absent, interface_state) do
      {:ok, Map.drop(result, [:dry_run])}
    else
      {:error, reason} ->
        _ = rollback(state, instance, :absent, current_config, interface_state)
        {:error, "#{reason}"}
    end
  end

  defp do_apply(
         state,
         instance,
         peers,
         action,
         current_config,
         desired_config,
         interface_state,
         result
       ) do
    with :ok <- backup(state, instance, action, current_config),
         :ok <- write_or_delete_config(state, instance, action, desired_config),
         :ok <- apply_to_kernel(state, instance, action, interface_state),
         :ok <- verify(state, instance, peers, action, interface_state) do
      {:ok, Map.drop(result, [:dry_run])}
    else
      {:error, reason} ->
        _ = rollback(state, instance, action, current_config, interface_state)
        {:error, "#{reason}"}
    end
  end

  defp backup(_state, _instance, :down, _current), do: :ok
  defp backup(_state, _instance, _action, nil), do: :ok

  defp backup(state, instance, _action, _current) do
    case state.config_store.backup_config(instance.protocol, instance.name) do
      :ok -> :ok
      {:error, reason} -> {:error, "Backup failed: #{reason}"}
    end
  end

  defp write_or_delete_config(state, instance, :absent, _config) do
    case state.config_store.delete_config(instance.protocol, instance.name) do
      :ok -> :ok
      {:error, reason} -> {:error, "Delete config failed: #{reason}"}
    end
  end

  defp write_or_delete_config(_state, _instance, :down, _config), do: :ok

  defp write_or_delete_config(state, instance, _action, config) do
    case state.config_store.write_config(instance.protocol, instance.name, config) do
      :ok -> :ok
      {:error, reason} -> {:error, "Write config failed: #{reason}"}
    end
  end

  defp apply_to_kernel(_state, _instance, :down, :absent), do: :ok
  defp apply_to_kernel(_state, _instance, :down, :down), do: :ok

  defp apply_to_kernel(state, instance, :down, _interface_state) do
    config_path = config_path(state, instance)

    case state.adapter.down(instance.protocol, instance.name, config_path) do
      :ok -> :ok
      {:error, reason} -> {:error, "down failed: #{reason}"}
    end
  end

  defp apply_to_kernel(_state, _instance, :absent, :absent) do
    :ok
  end

  defp apply_to_kernel(state, instance, :absent, _interface_state) do
    config_path = config_path(state, instance)

    case state.adapter.down(instance.protocol, instance.name, config_path) do
      :ok -> :ok
      {:error, reason} -> {:error, "down failed: #{reason}"}
    end
  end

  defp apply_to_kernel(state, instance, :restart, :up) do
    config_path = config_path(state, instance)

    with :ok <- state.adapter.down(instance.protocol, instance.name, config_path) do
      apply_to_kernel(state, instance, :up, :absent)
    end
  end

  defp apply_to_kernel(state, instance, :restart, interface_state) do
    apply_to_kernel(state, instance, :up, interface_state)
  end

  # A real `wg-quick up` fails with "already exists" when the interface is
  # present but administratively down, so we tear it down first.
  defp apply_to_kernel(state, instance, :up, :down) do
    config_path = config_path(state, instance)

    with :ok <- state.adapter.down(instance.protocol, instance.name, config_path) do
      apply_to_kernel(state, instance, :up, :absent)
    end
  end

  defp apply_to_kernel(state, instance, :up, :absent) do
    config_path = config_path(state, instance)

    case state.adapter.up(instance.protocol, instance.name, config_path) do
      :ok -> :ok
      {:error, reason} -> {:error, "up failed: #{reason}"}
    end
  end

  defp apply_to_kernel(state, instance, :up, :up) do
    config_path = config_path(state, instance)

    with {:ok, stripped} <-
           state.adapter.strip_config(instance.protocol, instance.name, config_path),
         {:ok, stripped_path} <- write_stripped_temp(stripped, instance.name) do
      try do
        case state.adapter.syncconf(instance.protocol, instance.name, stripped_path) do
          :ok -> :ok
          {:error, reason} -> {:error, "syncconf failed: #{reason}"}
        end
      after
        File.rm_rf(Path.dirname(stripped_path))
      end
    else
      {:error, reason} -> {:error, "strip failed: #{reason}"}
    end
  end

  # Внутренний хелпер, публичный только для тестирования прав доступа.
  @doc false
  def write_stripped_temp(content, instance_name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "wgm-#{instance_name}-#{:erlang.unique_integer([:positive])}"
      )

    stripped_path = Path.join(dir, "stripped.conf")

    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700),
         :ok <- File.write(stripped_path, content),
         :ok <- File.chmod(stripped_path, 0o600) do
      {:ok, stripped_path}
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp config_path(state, instance) do
    state.config_store.config_path(instance.protocol, instance.name)
  end

  defp verify(state, instance, _peers, :absent, _interface_state) do
    verify_absent(state, instance)
  end

  defp verify(_state, _instance, _peers, :down, :absent) do
    :ok
  end

  defp verify(state, instance, _peers, :down, _interface_state) do
    case state.adapter.interface_state(instance.name) do
      {:ok, :down} -> :ok
      {:ok, :unknown} -> verify_absent(state, instance)
      {:ok, :up} -> {:error, "Instance #{instance.name} is still up after stop"}
      {:error, _reason} -> :ok
    end
  end

  defp verify(state, instance, peers, action, _interface_state) when action in [:up, :restart] do
    with {:ok, dump} <- state.adapter.show_dump(instance.protocol, instance.name),
         {:ok, status} <- Parser.parse_dump(dump, instance.protocol),
         :ok <- verify_public_key(status, instance),
         :ok <- verify_peers(status, peers) do
      :ok
    else
      {:error, reason} -> {:error, "Verification failed: #{reason}"}
    end
  end

  defp verify_absent(state, instance) do
    case state.adapter.show_dump(instance.protocol, instance.name) do
      {:error, _} ->
        :ok

      {:ok, dump} ->
        case Parser.parse_dump(dump, instance.protocol) do
          {:ok, _} -> {:error, "Instance #{instance.name} is still present after removal"}
          {:error, _} -> :ok
        end
    end
  end

  defp verify_public_key(status, instance) do
    if status.public_key == instance.public_key do
      :ok
    else
      {:error, "Public key mismatch: expected #{instance.public_key}, got #{status.public_key}"}
    end
  end

  defp verify_peers(_status, []), do: :ok

  defp verify_peers(status, peers) do
    present_keys = MapSet.new(status.peers, & &1.public_key)
    expected_keys = MapSet.new(peers, & &1.public_key)

    if MapSet.subset?(expected_keys, present_keys) do
      :ok
    else
      missing = MapSet.difference(expected_keys, present_keys) |> Enum.join(", ")
      {:error, "Peers missing in applied config: #{missing}"}
    end
  end

  defp rollback(_state, _instance, _action, nil, _interface_state), do: :ok

  defp rollback(state, instance, :absent, current_config, _interface_state) do
    case state.config_store.write_config(instance.protocol, instance.name, current_config) do
      :ok -> :ok
      {:error, reason} -> {:error, "Rollback failed: #{reason}"}
    end
  end

  defp rollback(state, instance, _action, current_config, interface_state) do
    case state.config_store.write_config(instance.protocol, instance.name, current_config) do
      :ok ->
        apply_to_kernel(state, instance, :up, interface_state)

      {:error, reason} ->
        {:error, "Rollback failed: #{reason}"}
    end
  end
end
