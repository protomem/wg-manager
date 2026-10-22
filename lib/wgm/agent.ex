defmodule WGM.Agent do
  @moduledoc """
  Read-only агент узла. Хранит описание узла и список инстансов,
  по запросу возвращает структурированный статус через `WGM.Agent.Observer`.
  """

  use GenServer

  require Logger

  alias WGM.Agent.{Converger, Observer, Status}
  alias WGM.CLI.Adapter
  alias WGM.{Instance, Keygen}

  defstruct [
    :node,
    :instances,
    :adapter,
    :key_store,
    :config_store,
    :read_only,
    server_keys: %{}
  ]

  @doc """
  Запускает агента.

  Опции:
    - `:node` — `%WGM.Node{}`;
    - `:instances` — список `%WGM.Instance{}`;
    - `:adapter` — модуль, реализующая `WGM.CLI.Adapter` (по умолчанию
      `WGM.CLI.SystemAdapter`);
    - `:key_store` — модуль, реализующая `WGM.Agent.KeyStore` (по умолчанию
      `WGM.Agent.KeyStore.FileSystem`);
    - `:config_store` — модуль, реализующая `WGM.Agent.ConfigStore` (по
      умолчанию `WGM.Agent.ConfigStore.FileSystem`);
    - `:read_only` — `true`/`false`; в режиме read-only мутационные RPC
      (например, `generate_keypair`, `apply_instance`) возвращают ошибку.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Возвращает текущий статус узла.
  """
  @spec status(GenServer.server()) :: Status.t()
  def status(agent) do
    GenServer.call(agent, :status)
  end

  @doc """
  Генерирует серверную ключевую пару для инстанса.

  Приватный ключ сохраняется локально в состоянии агента, возвращается
  только публичный ключ.
  """
  @spec generate_keypair(GenServer.server(), String.t(), Adapter.protocol()) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_keypair(agent, instance_id, protocol) do
    GenServer.call(agent, {:generate_keypair, instance_id, protocol})
  end

  @doc """
  Применяет желаемое состояние инстанса на узле (converge).

  Опции см. в `WGM.Agent.Converger.converge/4`.
  """
  @spec apply_instance(
          GenServer.server(),
          WGM.Instance.t(),
          [WGM.Peer.t()],
          keyword()
        ) ::
          {:ok, map()} | {:error, String.t()}
  def apply_instance(agent, instance, peers, opts \\ []) do
    GenServer.call(agent, {:apply_instance, instance, peers, opts})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      node: opts[:node],
      instances: opts[:instances] || [],
      adapter: opts[:adapter] || WGM.CLI.SystemAdapter,
      key_store: opts[:key_store] || WGM.Agent.KeyStore.FileSystem,
      config_store: opts[:config_store] || WGM.Agent.ConfigStore.FileSystem,
      read_only: Keyword.get(opts, :read_only, false),
      server_keys: %{}
    }

    state = apply_saved_configs_at_boot(state)

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = Observer.observe(state.node, state.instances, state.adapter)
    {:reply, status, state}
  end

  def handle_call({:generate_keypair, _instance_id, _protocol}, _from, %{read_only: true} = state) do
    {:reply, {:error, "read-only mode"}, state}
  end

  def handle_call({:generate_keypair, instance_id, protocol}, _from, state) do
    with {:ok, private_key, new_state} <- ensure_private_key(state, instance_id, protocol),
         {:ok, public_key} <- new_state.adapter.pubkey(private_key, protocol) do
      {:reply, {:ok, public_key}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:apply_instance, _instance, _peers, _opts}, _from, %{read_only: true} = state) do
    {:reply, {:error, "read-only mode"}, state}
  end

  def handle_call({:apply_instance, instance, peers, opts}, _from, state) do
    result = Converger.converge(state, instance, peers, opts)
    new_state = update_instances_after_apply(state, instance, result, opts[:action] || :up)
    {:reply, result, new_state}
  end

  defp ensure_private_key(state, instance_id, protocol) do
    case Map.fetch(state.server_keys, instance_id) do
      {:ok, private_key} ->
        {:ok, private_key, state}

      :error ->
        case state.key_store.read_private_key(protocol, instance_id) do
          {:ok, private_key} ->
            new_state = %{
              state
              | server_keys: Map.put(state.server_keys, instance_id, private_key)
            }

            {:ok, private_key, new_state}

          {:error, _} ->
            generate_and_store_private_key(state, instance_id, protocol)
        end
    end
  end

  defp generate_and_store_private_key(state, instance_id, protocol) do
    case Keygen.generate_keypair(protocol, state.adapter) do
      {:ok, %{private_key: private_key}} ->
        :ok = state.key_store.write_private_key(protocol, instance_id, private_key)
        new_state = %{state | server_keys: Map.put(state.server_keys, instance_id, private_key)}
        {:ok, private_key, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_saved_configs_at_boot(%{read_only: true} = state), do: state

  defp apply_saved_configs_at_boot(state) do
    Enum.each(state.instances, fn instance ->
      if instance.target_state == :up do
        apply_saved_instance(state, instance)
      end
    end)

    state
  end

  defp apply_saved_instance(state, instance) do
    config_path = state.config_store.config_path(instance.protocol, instance.name)

    case state.config_store.read_config(instance.protocol, instance.name) do
      {:ok, _config} ->
        case state.adapter.interface_state(instance.name) do
          {:ok, :up} ->
            instance

          _ ->
            case state.adapter.up(instance.protocol, instance.name, config_path) do
              :ok ->
                instance

              {:error, reason} ->
                Logger.warning(
                  "Failed to apply saved config for #{instance.name} at boot: #{reason}"
                )

                instance
            end
        end

      {:error, :enoent} ->
        instance

      {:error, reason} ->
        Logger.warning(
          "Failed to read saved config for #{instance.name} at boot: #{inspect(reason)}"
        )

        instance
    end
  end

  defp update_instances_after_apply(state, instance, {:ok, _result}, :absent) do
    %{state | instances: Enum.reject(state.instances, &(&1.id == instance.id))}
  end

  defp update_instances_after_apply(state, instance, {:ok, _result}, action)
       when action in [:up, :down, :restart] do
    target_state = action_to_target_state(action)

    if Enum.any?(state.instances, &(&1.id == instance.id)) do
      new_instances =
        Enum.map(state.instances, fn
          %{id: id} when id == instance.id -> %{instance | target_state: target_state}
          other -> other
        end)

      %{state | instances: new_instances}
    else
      # Новый инстанс, созданный через apply_instance(:up/:restart), должен
      # попасть в наблюдение агента без рестарта (см. ревью wgm-65b6323).
      %{state | instances: [%{instance | target_state: target_state} | state.instances]}
    end
  end

  defp update_instances_after_apply(state, _instance, _result, _action), do: state

  defp action_to_target_state(action), do: Instance.target_state_for_action(action)
end
