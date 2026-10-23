defmodule WGM.ControllerCascadeTest do
  use ExUnit.Case

  alias WGM.{Cascade, Controller}
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
    attrs = %{id: id, name: id, address: "127.0.0.1", role: role}
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
    {:ok, ^inst_id} = Controller.create_instance(controller, "cmd-#{inst_id}", attrs)
    :ok
  end

  describe "create_cascade/3" do
    test "creates a cascade between entry and exit instances" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "entry-node", "entry-inst")
      :ok = register_instance(controller, "exit-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst",
        name: "main"
      }

      assert {:ok, "cascade-1"} = Controller.create_cascade(controller, "cmd-cascade", attrs)

      assert %Cascade{
               id: "cascade-1",
               entry_instance_id: "entry-inst",
               exit_instance_id: "exit-inst",
               name: "main"
             } = Controller.get_cascade(controller, "cascade-1")

      assert [%Cascade{id: "cascade-1"}] = Controller.list_cascades(controller)
    end

    test "returns error when entry instance does not exist" do
      controller = start_controller()
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "exit-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "missing",
        exit_instance_id: "exit-inst"
      }

      assert {:error, "Entry instance not found"} =
               Controller.create_cascade(controller, "cmd-cascade", attrs)
    end

    test "returns error when exit instance does not exist" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_instance(controller, "entry-node", "entry-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "missing"
      }

      assert {:error, "Exit instance not found"} =
               Controller.create_cascade(controller, "cmd-cascade", attrs)
    end

    test "returns error when entry and exit are on the same node" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_instance(controller, "entry-node", "entry-inst")
      :ok = register_instance(controller, "entry-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst"
      }

      assert {:error, "Entry and exit instances must be on different nodes"} =
               Controller.create_cascade(controller, "cmd-cascade", attrs)
    end

    test "returns error when entry node role is not entry" do
      controller = start_controller()
      :ok = register_node(controller, "standalone-node", :standalone)
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "standalone-node", "entry-inst")
      :ok = register_instance(controller, "exit-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst"
      }

      assert {:error, "Entry node role must be :entry"} =
               Controller.create_cascade(controller, "cmd-cascade", attrs)
    end

    test "returns error when exit node role is not exit" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_node(controller, "standalone-node", :standalone)
      :ok = register_instance(controller, "entry-node", "entry-inst")
      :ok = register_instance(controller, "standalone-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst"
      }

      assert {:error, "Exit node role must be :exit"} =
               Controller.create_cascade(controller, "cmd-cascade", attrs)
    end

    test "deduplicates repeated command id" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "entry-node", "entry-inst")
      :ok = register_instance(controller, "exit-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst"
      }

      assert {:ok, "cascade-1"} = Controller.create_cascade(controller, "cmd-cascade", attrs)
      assert {:ok, "cascade-1"} = Controller.create_cascade(controller, "cmd-cascade", attrs)
      assert length(Controller.list_cascades(controller)) == 1

      cascade_commands =
        Enum.filter(Controller.command_log(controller), &(&1.type == "create_cascade"))

      assert length(cascade_commands) == 1
    end
  end

  describe "delete_cascade/4" do
    test "deletes a cascade when confirmed" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "entry-node", "entry-inst")
      :ok = register_instance(controller, "exit-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst"
      }

      {:ok, "cascade-1"} = Controller.create_cascade(controller, "cmd-cascade", attrs)

      assert {:ok, "cascade-1"} =
               Controller.delete_cascade(controller, "cmd-delete", "cascade-1", true)

      assert Controller.get_cascade(controller, "cascade-1") == nil
    end

    test "requires confirmation" do
      controller = start_controller()
      :ok = register_node(controller, "entry-node", :entry)
      :ok = register_node(controller, "exit-node", :exit)
      :ok = register_instance(controller, "entry-node", "entry-inst")
      :ok = register_instance(controller, "exit-node", "exit-inst")

      attrs = %{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst"
      }

      {:ok, "cascade-1"} = Controller.create_cascade(controller, "cmd-cascade", attrs)

      assert {:error, "Destructive action delete_cascade requires confirmation"} =
               Controller.delete_cascade(controller, "cmd-delete", "cascade-1", false)
    end
  end
end
