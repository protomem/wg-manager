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

  @spec set_keypair(String.t(), String.t(), WGM.CLI.Adapter.protocol(), String.t()) :: :ok
  def set_keypair(node_id, instance_id, protocol, public_key) do
    :ets.insert(__MODULE__, {{:keypair, node_id, instance_id, protocol}, public_key})
    :ok
  end

  @spec set_apply_result(String.t(), String.t(), {:ok, map()} | {:error, String.t()}) :: :ok
  def set_apply_result(node_id, instance_id, result) do
    :ets.insert(__MODULE__, {{:apply, node_id, instance_id}, result})
    :ok
  end

  @spec set_check_result(
          String.t(),
          atom(),
          String.t() | [String.t()] | nil,
          {
            :ok,
            WGM.Check.Result.t()
          }
          | {:error, String.t()}
        ) :: :ok
  def set_check_result(node_id, kind, target, result) do
    :ets.insert(__MODULE__, {{:check, node_id, kind, target}, result})
    :ok
  end

  @spec calls() :: [tuple()]
  def calls do
    case :ets.lookup(__MODULE__, :calls) do
      [{_, calls}] -> Enum.reverse(calls)
      [] -> []
    end
  end

  @impl true
  def status(%Node{id: node_id}) do
    case :ets.lookup(__MODULE__, {:status, node_id}) do
      [{_, status}] -> status
      [] -> {:error, "No status fixture for #{node_id}"}
    end
  end

  @impl true
  def generate_keypair(%Node{id: node_id}, instance_id, protocol) do
    case :ets.lookup(__MODULE__, {:keypair, node_id, instance_id, protocol}) do
      [{_, public_key}] -> {:ok, public_key}
      [] -> {:error, "No keypair fixture for #{node_id}/#{instance_id}/#{protocol}"}
    end
  end

  @impl true
  def apply_instance(%Node{id: node_id}, %WGM.Instance{id: instance_id}, _peers, opts) do
    record_call({:apply_instance, node_id, instance_id, opts[:action]})

    case :ets.lookup(__MODULE__, {:apply, node_id, instance_id}) do
      [{_, result}] -> result
      [] -> {:error, "No apply fixture for #{node_id}/#{instance_id}"}
    end
  end

  @impl true
  def check(%Node{id: node_id}, kind, target) do
    record_call({:check, node_id, kind, target})

    case :ets.lookup(__MODULE__, {:check, node_id, kind, target}) do
      [{_, result}] -> result
      [] -> {:error, "No check fixture for #{node_id}/#{kind}"}
    end
  end

  defp record_call(call) do
    calls =
      case :ets.lookup(__MODULE__, :calls) do
        [{_, list}] -> [call | list]
        [] -> [call]
      end

    :ets.insert(__MODULE__, {:calls, calls})
  end
end
