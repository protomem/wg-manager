defmodule WGM.Controller.AgentAdapter.Distribution do
  @moduledoc """
  Реализация адаптера агента через Erlang distribution.

  Ожидает, что на удалённом узле агент зарегистрирован под именем
  `:wgm_agent` и нода называется `wgm_agent@<address>`.
  """

  @behaviour WGM.Controller.AgentAdapter

  alias WGM.Node, as: WGMNode

  @impl true
  def status(%WGMNode{address: address}) do
    call_agent(address, WGM.Agent, :status, [:wgm_agent])
  end

  @impl true
  def generate_keypair(%WGMNode{address: address}, instance_id, protocol) do
    call_agent(address, WGM.Agent, :generate_keypair, [:wgm_agent, instance_id, protocol])
  end

  defp call_agent(address, module, function, args) do
    node_name = node_name(address)

    case Node.connect(node_name) do
      true ->
        try do
          :erpc.call(node_name, module, function, args, 5_000)
        catch
          kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
        end

      false ->
        {:error, "Node #{node_name} is not reachable"}

      :ignored ->
        {:error, "Erlang distribution is not enabled"}
    end
  end

  defp node_name(address), do: String.to_atom("wgm_agent@#{address}")
end
