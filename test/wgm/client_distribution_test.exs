defmodule WGM.ClientDistributionTest do
  use ExUnit.Case

  alias WGM.Client

  @cookie_str "wgm_test_cookie"
  @cookie_atom :wgm_test_cookie

  setup do
    name = :"wgm_client_dist_#{System.unique_integer([:positive])}"
    {:ok, _} = :net_kernel.start(name, %{name_domain: :shortnames})
    Node.set_cookie(@cookie_atom)

    on_exit(fn ->
      :net_kernel.stop()
    end)

    :ok
  end

  test "connects from a hidden node" do
    controller = start_controller_peer()
    client = start_hidden_client_peer()

    assert Node.connect(client) == true

    assert {:ok, ^controller} = :erpc.call(client, Client, :connect, [controller, @cookie_str])

    assert :erpc.call(client, Node, :list, [:visible]) == []
    assert controller in :erpc.call(client, Node, :list, [:hidden])
    assert controller in :erpc.call(client, Node, :list, [:connected])
  end

  test "hidden client does not pull neighbouring agent nodes" do
    controller = start_controller_peer()
    agent = start_agent_peer(controller)
    client = start_hidden_client_peer()

    assert Node.connect(client) == true

    assert {:ok, ^controller} = :erpc.call(client, Client, :connect, [controller, @cookie_str])

    connected = :erpc.call(client, Node, :list, [:connected])
    assert controller in connected
    refute agent in connected
  end

  test "returns error on a visible node with instruction to use --hidden" do
    controller = start_controller_peer()

    assert {:error, reason} = Client.connect(controller, @cookie_str)
    assert reason =~ "hidden"
    assert reason =~ "--hidden"
  end

  defp start_controller_peer do
    pa = Enum.flat_map(:code.get_path(), fn p -> [~c"-pa", p] end)
    name = :"wgm_ctrl_#{System.unique_integer([:positive])}"

    {:ok, pid, node} =
      :peer.start(%{
        name: name,
        args: [to_charlist("-setcookie"), to_charlist(@cookie_str)] ++ pa
      })

    on_exit(fn -> :peer.stop(pid) end)
    node
  end

  defp start_hidden_client_peer do
    pa = Enum.flat_map(:code.get_path(), fn p -> [~c"-pa", p] end)
    name = :"wgm_hid_client_#{System.unique_integer([:positive])}"

    {:ok, pid, node} =
      :peer.start(%{
        name: name,
        args:
          [
            to_charlist("-setcookie"),
            to_charlist(@cookie_str),
            to_charlist("-hidden")
          ] ++ pa
      })

    on_exit(fn -> :peer.stop(pid) end)
    node
  end

  defp start_agent_peer(controller) do
    pa = Enum.flat_map(:code.get_path(), fn p -> [~c"-pa", p] end)
    name = :"wgm_agent_#{System.unique_integer([:positive])}"

    {:ok, pid, node} =
      :peer.start(%{
        name: name,
        args: [to_charlist("-setcookie"), to_charlist(@cookie_str)] ++ pa
      })

    assert Node.connect(node) == true
    :erpc.call(node, Node, :connect, [controller])

    on_exit(fn -> :peer.stop(pid) end)
    node
  end
end
