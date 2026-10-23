if Mix.env() != :prod do
  defmodule WGM.CLI.FakeAdapter do
    @moduledoc """
    CLI-адаптер-заглушка. Генерирует детерминированные "ключи" на основе
    счётчика вызовов; возвращает зарегистрированные `show dump` и состояния
    интерфейсов.

    Используется в тестах и демо; в production применяется
    `WGM.CLI.SystemAdapter`.

    Хелперы:
      - `start/0` — создать/сбросить внутреннее хранилище фикстур.
      - `set_dump/3` — задать текущий вывод `show dump` для `{protocol, interface}`.
      - `set_pending_up_dump/3` — зарегистрировать dump, который `up/3` установит
        после создания интерфейса.
      - `set_interface_state/2` — задать состояние интерфейса.
      - `reset/0` — очистить фикстуры.
    """

    @behaviour WGM.CLI.Adapter

    @doc """
    Создаёт именованную ETS-таблицу для хранения фикстур.
    """
    @spec start() :: :ok
    def start do
      if :ets.whereis(__MODULE__) == :undefined do
        :ets.new(__MODULE__, [:public, :named_table, read_concurrency: true])
      else
        :ets.delete_all_objects(__MODULE__)
      end

      :ok
    end

    @impl true
    def genkey(_protocol) do
      {:ok, "private-key-#{next_counter()}"}
    end

    @impl true
    def pubkey(private_key, _protocol) do
      {:ok, "public-for-#{private_key}"}
    end

    @impl true
    def genpsk do
      {:ok, "psk-#{next_counter()}"}
    end

    @impl true
    def show_dump(protocol, interface) do
      case :ets.lookup(__MODULE__, {:dump, protocol, interface}) do
        [{_, dump}] -> {:ok, dump}
        [] -> {:error, "No dump fixture for #{protocol} #{interface}"}
      end
    end

    @impl true
    def interface_state(interface) do
      case :ets.lookup(__MODULE__, {:state, interface}) do
        [{_, state}] -> {:ok, state}
        [] -> {:error, "Interface #{interface} not found"}
      end
    end

    @impl true
    def syncconf(protocol, interface, config_path) do
      record_call({:syncconf, protocol, interface, config_path})
      :ok
    end

    @impl true
    def strip_config(protocol, interface, config_path) do
      record_call({:strip_config, protocol, interface, config_path})

      case :ets.lookup(__MODULE__, {:strip, protocol, interface}) do
        [{_, content}] -> {:ok, content}
        [] -> {:ok, WGM.ConfigGenerator.strip_quick_keys("[Interface]\nAddress = 10.0.0.1/24\n")}
      end
    end

    @impl true
    def up(protocol, interface, config_path) do
      case record_call({:up, protocol, interface, config_path}) do
        :ok ->
          # `wg-quick up` fails when the interface already exists, even if it
          # is administratively down. Only create it when it is truly absent.
          if interface_exists?(interface) do
            {:error, "already exists"}
          else
            set_interface_state(interface, :up)
            install_pending_dump(protocol, interface)
            :ok
          end

        other ->
          other
      end
    end

    @impl true
    def down(protocol, interface, config_path) do
      case record_call({:down, protocol, interface, config_path}) do
        :ok ->
          # `wg-quick down` removes the interface and its dump disappears with it.
          # A subsequent `up` rebuilds the interface from the current config and
          # produces a fresh dump; tests must set the new fixture explicitly.
          # Like the real tool, we fail when the interface is not present.
          # When configured, we also model the tool's dependency on the config
          # file (see `set_down_requires_existing_config/3`).
          with :ok <- require_config_if_needed(protocol, interface),
               true <- interface_exists?(interface) do
            :ets.delete(__MODULE__, {:state, interface})
            :ets.delete(__MODULE__, {:dump, protocol, interface})
            :ok
          else
            false -> {:error, "Interface #{interface} does not exist"}
            {:error, reason} -> {:error, reason}
          end

        other ->
          other
      end
    end

    @doc """
    Sets the current `show dump` fixture for `{protocol, interface}`.

    This represents the dump of an already existing interface. It is removed by
    `down/3` just like a real interface disappears from `wg show dump`.
    """
    def set_dump(protocol, interface, dump) do
      :ets.insert(__MODULE__, {{:dump, protocol, interface}, dump})
    end

    @doc """
    Registers a dump fixture that `up/3` will install after creating the interface.

    This survives the internal `down → up` sequence in `Converger` and lets tests
    provide the post-up dump that corresponds to the freshly applied config.
    """
    def set_pending_up_dump(protocol, interface, dump) do
      :ets.insert(__MODULE__, {{:up_dump, protocol, interface}, dump})
    end

    def set_interface_state(interface, state) do
      :ets.insert(__MODULE__, {{:state, interface}, state})
    end

    def reset do
      :ets.delete_all_objects(__MODULE__)
    end

    def calls do
      case :ets.lookup(__MODULE__, :calls) do
        [{_, calls}] -> Enum.reverse(calls)
        [] -> []
      end
    end

    def set_syncconf_result(protocol, interface, result) do
      :ets.insert(__MODULE__, {{:syncconf_result, protocol, interface}, result})
    end

    def set_up_result(protocol, interface, result) do
      :ets.insert(__MODULE__, {{:up_result, protocol, interface}, result})
    end

    def set_down_result(protocol, interface, result) do
      :ets.insert(__MODULE__, {{:down_result, protocol, interface}, result})
    end

    @doc """
    Makes `down/3` fail when the config file is not present in the fake store.

    Models the real `wg-quick down` dependency on the config file: the tool
    needs the file to tear the interface down.
    """
    def set_down_requires_existing_config(protocol, interface, required \\ true) do
      :ets.insert(__MODULE__, {{:down_requires_config, protocol, interface}, required})
    end

    @doc """
    Keeps the config-existence marker in sync with the fake config store.

    Models whether the config file exists for the instance and is used together
    with `set_down_requires_existing_config/3` to reflect the real `wg-quick down`
    dependency on the config file. Callers should use this function instead of
    touching the adapter's internal ETS table directly.
    """
    def set_config_exists(protocol, interface, exists \\ true) do
      :ets.insert(__MODULE__, {{:config_exists, protocol, interface}, exists})
    end

    def set_strip_content(protocol, interface, content) do
      :ets.insert(__MODULE__, {{:strip, protocol, interface}, content})
    end

    defp record_call(call) do
      :ets.update_counter(__MODULE__, :counter, {2, 1}, {:counter, 0})

      calls =
        case :ets.lookup(__MODULE__, :calls) do
          [{_, list}] -> [call | list]
          [] -> [call]
        end

      :ets.insert(__MODULE__, {:calls, calls})
      maybe_apply_result(call)
    end

    defp maybe_apply_result({:syncconf, protocol, interface, _}),
      do: lookup_result(:syncconf_result, protocol, interface)

    defp maybe_apply_result({:up, protocol, interface, _}),
      do: lookup_result(:up_result, protocol, interface)

    defp maybe_apply_result({:down, protocol, interface, _}),
      do: lookup_result(:down_result, protocol, interface)

    defp maybe_apply_result({_other, _protocol, _interface, _config_path}) do
      :ok
    end

    defp lookup_result(key, protocol, interface) do
      case :ets.lookup(__MODULE__, {key, protocol, interface}) do
        [{_, result}] -> result
        [] -> :ok
      end
    end

    defp require_config_if_needed(protocol, interface) do
      case :ets.lookup(__MODULE__, {:down_requires_config, protocol, interface}) do
        [{_, true}] ->
          case :ets.lookup(__MODULE__, {:config_exists, protocol, interface}) do
            [{_, true}] -> :ok
            _ -> {:error, "Config file does not exist"}
          end

        _ ->
          :ok
      end
    end

    defp interface_exists?(interface) do
      case :ets.lookup(__MODULE__, {:state, interface}) do
        [] -> false
        [{_, :unknown}] -> false
        _ -> true
      end
    end

    defp install_pending_dump(protocol, interface) do
      case :ets.lookup(__MODULE__, {:up_dump, protocol, interface}) do
        [{_, dump}] ->
          :ets.insert(__MODULE__, {{:dump, protocol, interface}, dump})
          :ets.delete(__MODULE__, {{:up_dump, protocol, interface}})

        [] ->
          :ok
      end
    end

    defp next_counter do
      :ets.update_counter(__MODULE__, :counter, {2, 1}, {:counter, 0})
    end
  end
end
