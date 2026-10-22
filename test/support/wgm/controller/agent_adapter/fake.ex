defmodule WGM.Controller.AgentAdapter.Fake do
  @moduledoc """
  Тестовый адаптер подключения контроллера к агентам.
  """

  @behaviour WGM.Controller.AgentAdapter

  alias WGM.Node

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

  @spec set_status(String.t(), {:ok, WGM.Agent.Status.t()} | {:error, String.t()}) :: :ok
  def set_status(node_id, status) do
    :ets.insert(__MODULE__, {{:status, node_id}, status})
    :ok
  end

  @impl true
  def status(%Node{id: node_id}) do
    case :ets.lookup(__MODULE__, {:status, node_id}) do
      [{_, status}] -> status
      [] -> {:error, "No status fixture for #{node_id}"}
    end
  end
end
