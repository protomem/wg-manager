defmodule WGM.ControllerSwitchProtocolTest do
  use ExUnit.Case

  alias WGM.{Controller, Instance}
  alias WGM.Controller.AgentAdapter.Fake, as: FakeAgentAdapter

  setup do
    FakeAgentAdapter.start()
    :ok
  end

  defp start_controller do
    {:ok, controller} =
      Controller.start_link(
        db_path: ":memory:",
        agent_adapter: FakeAgentAdapter,
        keygen_adapter: WGM.CLI.FakeAdapter
      )

    controller
  end

  defp register_node(controller, id, role) do
    attrs = %{id: id, name: id, address: "193.233.91.130", role: role}
    {:ok, ^id} = Controller.register_node(controller, "cmd-#{id}", attrs)
    :ok
  end

  defp register_instance(controller, node_id, inst_id, protocol) do
    attrs = %{
      id: inst_id,
      node_id: node_id,
      name: inst_id,
      protocol: protocol,
      listen_port: 51820,
      subnet: "10.0.0.0/24",
      address: "10.0.0.1/24"
    }

    FakeAgentAdapter.set_keypair(node_id, inst_id, protocol, "pub-#{inst_id}")

    if protocol == :awg do
      FakeAgentAdapter.set_header_protection_key(node_id, inst_id, "header-#{inst_id}")
    end

    {:ok, ^inst_id} = Controller.create_instance(controller, "cmd-#{inst_id}", attrs)
    :ok
  end

  defp register_peer(controller, instance_id, peer_id) do
    attrs = %{
      id: peer_id,
      instance_id: instance_id,
      name: "laptop",
      allowed_ips: "10.0.0.2/32",
      address: "10.0.0.2/32",
      endpoint: "193.233.91.130:51820"
    }

    {:ok, ^peer_id} = Controller.create_peer(controller, "cmd-#{peer_id}", attrs)
    :ok
  end

  describe "switch_protocol/5" do
    test "switches WG instance to AWG and regenerates client config" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_instance(controller, "entry-node", "inst-1", :wg)
      :ok = register_peer(controller, "inst-1", "peer-1")

      {:ok, wg_config} =
        Controller.store_client_config(controller, "cmd-config", "peer-1", "193.233.91.130:51820")

      assert wg_config =~ "[Interface]"

      FakeAgentAdapter.set_keypair("entry-node", "inst-1", :awg, "pub-awg")
      FakeAgentAdapter.set_header_protection_key("entry-node", "inst-1", "header-awg")
      FakeAgentAdapter.set_apply_result("entry-node", "inst-1", {:ok, %{}})

      assert {:ok, "inst-1"} =
               Controller.switch_protocol(controller, "cmd-switch", "inst-1", :awg, true)

      assert %Instance{protocol: :awg, public_key: "pub-awg", awg_params: %{jc: 4}} =
               Controller.get_instance(controller, "inst-1")

      awg_config = Controller.get_client_config(controller, "peer-1")
      assert awg_config =~ "Jc = 4"
      refute awg_config == wg_config

      apply_calls = FakeAgentAdapter.calls()
      assert Enum.any?(apply_calls, &(&1 == {:apply_instance, "entry-node", "inst-1", :up}))
    end

    test "switches AWG instance to WG" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_instance(controller, "entry-node", "inst-1", :awg)
      :ok = register_peer(controller, "inst-1", "peer-1")

      FakeAgentAdapter.set_keypair("entry-node", "inst-1", :wg, "pub-wg")
      FakeAgentAdapter.set_apply_result("entry-node", "inst-1", {:ok, %{}})

      assert {:ok, "inst-1"} =
               Controller.switch_protocol(controller, "cmd-switch", "inst-1", :wg, true)

      assert %Instance{protocol: :wg, awg_params: nil} =
               Controller.get_instance(controller, "inst-1")
    end

    test "requires confirmation" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_instance(controller, "entry-node", "inst-1", :wg)

      assert {:error, "Destructive action switch_protocol requires confirmation"} =
               Controller.switch_protocol(controller, "cmd-switch", "inst-1", :awg, false)
    end

    test "returns error when protocol is the same" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_instance(controller, "entry-node", "inst-1", :wg)

      assert {:error, "Protocol is already wg"} =
               Controller.switch_protocol(controller, "cmd-switch", "inst-1", :wg, true)
    end
  end
end
