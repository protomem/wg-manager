defmodule WGM.ClientTest do
  use ExUnit.Case

  alias WGM.{Client, Controller, Instance, Peer}
  alias WGM.Controller.AgentAdapter.Fake

  setup do
    Fake.start()
    :ok
  end

  describe "help/0" do
    test "returns usage information" do
      help = Client.help()

      assert help =~ "WGM.Client"
      assert help =~ "connect"
      assert help =~ "status"
      assert help =~ "list_instances"
      assert help =~ "list_peers"
    end
  end

  describe "connect/2" do
    test "returns error when Erlang distribution is not enabled" do
      assert :erlang.node() == :nonode@nohost

      assert {:error, "Erlang distribution is not enabled"} =
               Client.connect("wgm_controller@127.0.0.1", "cookie")
    end
  end

  describe "status/1" do
    test "returns aggregated status from controller" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")

      agent_status = %WGM.Agent.Status{
        node_id: "node-1",
        timestamp: DateTime.utc_now(),
        instances: []
      }

      Fake.set_status("node-1", {:ok, agent_status})

      assert {:ok, [status]} = Client.status(node())
      assert status.node_id == "node-1"
      assert status.node_name == "node-1"
      assert status.online
      assert status.agent_status.node_id == "node-1"
    end

    test "returns offline status when agent is unreachable" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")

      assert {:ok, [status]} = Client.status(node())
      assert status.node_id == "node-1"
      refute status.online
      assert status.agent_status == nil
    end

    test "returns error when controller is not running" do
      assert {:error, _reason} = Client.status(node())
    end
  end

  describe "desired state queries" do
    test "list_nodes/1, list_instances/1, list_peers/1 return controller data" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")
      :ok = register_instance(controller, "node-1", "inst-1")
      :ok = register_peer(controller, "inst-1", "peer-1")

      assert {:ok, [%WGM.Node{id: "node-1"}]} = Client.list_nodes(node())
      assert {:ok, [%Instance{id: "inst-1"}]} = Client.list_instances(node())
      assert {:ok, [%Peer{id: "peer-1"}]} = Client.list_peers(node())
    end
  end

  defp start_controller do
    {:ok, controller} =
      Controller.start_link(
        db_path: ":memory:",
        name: :wgm_controller,
        agent_adapter: Fake,
        keygen_adapter: WGM.CLI.FakeAdapter
      )

    on_exit(fn ->
      if pid = Process.whereis(:wgm_controller) do
        Process.exit(pid, :shutdown)
      end
    end)

    controller
  end

  defp register_node(controller, id) do
    attrs = %{id: id, name: id, address: "193.233.91.130", role: :entry}
    assert {:ok, ^id} = Controller.register_node(controller, "cmd-#{id}", attrs)
    :ok
  end

  defp register_instance(controller, node_id, id) do
    Fake.set_keypair(node_id, id, :wg, "server-pub-#{id}")

    attrs = %{
      id: id,
      node_id: node_id,
      name: "wg1",
      protocol: :wg,
      listen_port: 51820,
      subnet: "10.0.0.0/24",
      address: "10.0.0.1/24"
    }

    assert {:ok, ^id} = Controller.create_instance(controller, "cmd-#{id}", attrs)
    :ok
  end

  defp register_peer(controller, instance_id, id) do
    attrs = %{
      id: id,
      instance_id: instance_id,
      name: "laptop",
      allowed_ips: "10.0.0.2/32",
      address: "10.0.0.2/32"
    }

    assert {:ok, ^id} = Controller.create_peer(controller, "cmd-#{id}", attrs)
    :ok
  end
end
