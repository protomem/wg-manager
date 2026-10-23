if Mix.env() != :prod do
  defmodule WGM.HealthCheck.FakeAdapter do
    @moduledoc """
    Тестовый адаптер активных проверок.
    """

    @behaviour WGM.HealthCheck.Adapter

    @spec start() :: :ok
    def start do
      if :ets.whereis(__MODULE__) == :undefined do
        :ets.new(__MODULE__, [:public, :named_table, read_concurrency: true])
      else
        :ets.delete_all_objects(__MODULE__)
      end

      :ok
    end

    @spec reset() :: :ok
    def reset do
      :ets.delete_all_objects(__MODULE__)
      :ok
    end

    @spec set_ping_result(String.t(), {:ok, String.t()} | {:error, String.t()}) :: :ok
    def set_ping_result(target, result) do
      :ets.insert(__MODULE__, {{:ping, target}, result})
      :ok
    end

    @spec set_end_to_end_result([String.t()], {:ok, String.t()} | {:error, String.t()}) :: :ok
    def set_end_to_end_result(route, result) do
      :ets.insert(__MODULE__, {{:end_to_end, route}, result})
      :ok
    end

    @impl true
    def ping(target) do
      case :ets.lookup(__MODULE__, {:ping, target}) do
        [{_, result}] -> result
        [] -> {:error, "No ping fixture for #{target}"}
      end
    end

    @impl true
    def end_to_end(route) do
      case :ets.lookup(__MODULE__, {:end_to_end, route}) do
        [{_, result}] -> result
        [] -> {:error, "No end_to_end fixture for #{inspect(route)}"}
      end
    end
  end
end
