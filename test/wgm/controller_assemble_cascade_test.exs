defmodule WGM.ControllerAssembleCascadeTest do
  use ExUnit.Case

  alias WGM.{Controller, Instance, Peer}
  alias WGM.Controller.AgentAdapter.Fake, as: FakeAgentAdapter

  setup do
    FakeAgentAdapter.start()
    :ok
  end

  defp start_controller(opts \\ []) do
    opts =
      Keyword.merge(
        [
          db_path: ":memory:",
          agent_adapter: FakeAgentAdapter,
          keygen_adapter: WGM.CLI.FakeAdapter
        ],
        opts
      )

    {:ok, controller} = Controller.start_link(opts)
    controller
  end

  defp register_node(controller, id, role) do
    attrs = %{id: id, name: id, address: "193.233.91.130", role: role}
    {:ok, ^id} = Controller.register_node(controller, "cmd-#{id}", attrs)
    :ok
  end

  defp register_instance(controller, node_id, inst_id, protocol \\ :wg) do
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

  describe "assemble_cascade/4" do
    test "creates transit instances, peers and converges them" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "entry-node", "entry-wg")
      :ok = register_instance(controller, "exit-node", "exit-wg")

      FakeAgentAdapter.set_keypair(
        "entry-node",
        "cascade-entry-transit",
        :awg,
        "pub-entry-transit"
      )

      FakeAgentAdapter.set_keypair("exit-node", "cascade-exit", :awg, "pub-exit")

      FakeAgentAdapter.set_header_protection_key(
        "entry-node",
        "cascade-entry-transit",
        "header-entry-transit"
      )

      FakeAgentAdapter.set_header_protection_key("exit-node", "cascade-exit", "header-exit")
      FakeAgentAdapter.set_apply_result("entry-node", "cascade-entry-transit", {:ok, %{}})
      FakeAgentAdapter.set_apply_result("exit-node", "cascade-exit", {:ok, %{}})

      {:ok, "cascade-1"} =
        Controller.create_cascade(controller, "cmd-cascade", %{
          id: "cascade-1",
          entry_instance_id: "entry-wg",
          exit_instance_id: "exit-wg"
        })

      assert {:ok, result} =
               Controller.assemble_cascade(controller, "cmd-assemble", "cascade-1", confirm: true)

      assert result.cascade_id == "cascade-1"
      assert result.entry_transit_instance_id == "cascade-entry-transit"
      assert result.exit_instance_id == "cascade-exit"

      assert %Instance{protocol: :awg} =
               Controller.get_instance(controller, "cascade-entry-transit")

      assert %Instance{protocol: :awg} = Controller.get_instance(controller, "cascade-exit")

      entry_peers = Controller.list_peers(controller, "cascade-entry-transit")
      exit_peers = Controller.list_peers(controller, "cascade-exit")

      assert length(entry_peers) == 1
      assert length(exit_peers) == 1

      assert [%Peer{allowed_ips: "0.0.0.0/0"}] = entry_peers
      assert [%Peer{allowed_ips: "10.0.0.0/24,10.200.0.1/32"}] = exit_peers

      [entry_peer] = entry_peers
      [exit_peer] = exit_peers
      assert entry_peer.preshared_key == exit_peer.preshared_key
      assert entry_peer.preshared_key not in [nil, ""]

      entry_transit = Controller.get_instance(controller, "cascade-entry-transit")
      assert entry_transit.table == "off"

      assert Enum.any?(
               entry_transit.post_up,
               &String.contains?(&1, "ip rule add from 10.0.0.0/24")
             )

      assert Enum.any?(
               entry_transit.post_up,
               &String.contains?(&1, "ip route add default dev %i")
             )

      apply_calls = FakeAgentAdapter.calls()

      assert Enum.any?(
               apply_calls,
               &(&1 == {:apply_instance, "entry-node", "cascade-entry-transit", :up})
             )

      assert Enum.any?(
               apply_calls,
               &(&1 == {:apply_instance, "exit-node", "cascade-exit", :up})
             )
    end

    test "requires confirmation" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "entry-node", "entry-wg")
      :ok = register_instance(controller, "exit-node", "exit-wg")

      {:ok, "cascade-1"} =
        Controller.create_cascade(controller, "cmd-cascade", %{
          id: "cascade-1",
          entry_instance_id: "entry-wg",
          exit_instance_id: "exit-wg"
        })

      assert {:error, "Destructive action assemble_cascade requires confirmation"} =
               Controller.assemble_cascade(controller, "cmd-assemble", "cascade-1", [])
    end
  end
end
