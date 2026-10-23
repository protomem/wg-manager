defmodule WGM.ClientCheckTest do
  use ExUnit.Case

  alias WGM.{Check, Client, Controller}
  alias WGM.Controller.AgentAdapter.Fake

  setup do
    Fake.start()
    :ok
  end

  describe "check_results/1" do
    test "returns latest check results from controller" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")

      now = DateTime.utc_now()

      Fake.set_check_result(
        "node-1",
        :ping,
        "1.1.1.1",
        {:ok,
         %Check.Result{
           node_id: "node-1",
           instance_id: nil,
           peer_id: nil,
           kind: :ping,
           status: :ok,
           detail: "ping ok",
           checked_at: now,
           last_success_at: now
         }}
      )

      assert {:ok, result} = Controller.run_active_check(controller, "node-1", :ping, "1.1.1.1")
      assert result.status == :ok

      assert {:ok, [stored]} = Client.check_results(Node.self())
      assert stored.node_id == "node-1"
      assert stored.kind == :ping
    end
  end

  describe "run_active_check/4" do
    test "runs active check through controller" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")

      now = DateTime.utc_now()

      Fake.set_check_result(
        "node-1",
        :ping,
        "1.1.1.1",
        {:ok,
         %Check.Result{
           node_id: "node-1",
           instance_id: nil,
           peer_id: nil,
           kind: :ping,
           status: :ok,
           detail: "ping 1.1.1.1 ok",
           checked_at: now,
           last_success_at: now
         }}
      )

      assert {:ok, result} =
               Client.run_active_check(Node.self(), "node-1", :ping, "1.1.1.1")

      assert result.status == :ok
      assert result.detail == "ping 1.1.1.1 ok"
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
end
