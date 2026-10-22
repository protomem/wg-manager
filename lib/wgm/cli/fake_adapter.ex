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
      - `set_dump/3` — задать вывод `show dump` для `{protocol, interface}`.
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

    def set_dump(protocol, interface, dump) do
      :ets.insert(__MODULE__, {{:dump, protocol, interface}, dump})
    end

    def set_interface_state(interface, state) do
      :ets.insert(__MODULE__, {{:state, interface}, state})
    end

    def reset do
      :ets.delete_all_objects(__MODULE__)
    end

    defp next_counter do
      :ets.update_counter(__MODULE__, :counter, {2, 1}, {:counter, 0})
    end
  end
end
