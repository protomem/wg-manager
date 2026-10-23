defmodule WGM.ClientCascadeTest do
  use ExUnit.Case

  alias WGM.{Cascade, Client, Controller}
  alias WGM.Controller.AgentAdapter.Fake

  setup do
    Fake.start()
    :ok
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

  describe "cascade client API" do
    test "create_cascade, list_cascades, get_cascade, delete_cascade" do
      controller = start_controller()

      :ok =
        register_node(controller, "entry-node", :entry, "193.233.91.130")

      :ok = register_node(controller, "exit-node", :exit, "5.129.219.31")
      :ok = register_instance(controller, "entry-node", "entry-inst")
      :ok = register_instance(controller, "exit-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst",
        name: "main"
      }

      assert {:ok, "cascade-1"} = Client.create_cascade(node(), "cmd-cascade", attrs)
      assert {:ok, [%Cascade{id: "cascade-1"}]} = Client.list_cascades(node())
      assert {:ok, %Cascade{id: "cascade-1"}} = Client.get_cascade(node(), "cascade-1")

      assert {:error, "Destructive action delete_cascade requires confirmation"} =
               Client.delete_cascade(node(), "cmd-delete", "cascade-1")

      assert {:ok, "cascade-1"} =
               Client.delete_cascade(node(), "cmd-delete", "cascade-1", confirm: true)

      assert {:ok, nil} = Client.get_cascade(node(), "cascade-1")
    end
  end

  defp register_node(controller, id, role, address) do
    attrs = %{id: id, name: id, address: address, role: role}
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

    Fake.set_keypair(node_id, inst_id, protocol, "pub-#{inst_id}")
    {:ok, ^inst_id} = Controller.create_instance(controller, "cmd-#{inst_id}", attrs)
    :ok
  end
end
