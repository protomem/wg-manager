defmodule WGM.Controller.RepoTest do
  use ExUnit.Case

  alias WGM.{Check, Node}
  alias WGM.Controller.Repo

  describe "open/1" do
    test "creates the database file with 0600 permissions" do
      dir = Path.join(System.tmp_dir!(), "wgm-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "controller.db")

      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, conn} = Repo.open(path)
      assert :ok = Repo.migrate(conn)

      stat = File.stat!(path)
      assert Bitwise.band(stat.mode, 0o777) == 0o600
    end

    test "works with in-memory database" do
      assert {:ok, conn} = Repo.open(":memory:")
      assert :ok = Repo.migrate(conn)
    end
  end

  describe "check results" do
    test "stores and retrieves latest results" do
      assert {:ok, conn} = Repo.open(":memory:")
      assert :ok = Repo.migrate(conn)

      :ok = Repo.insert_node(conn, sample_node("node-1"))

      t1 = DateTime.from_iso8601("2026-10-23T10:00:00Z") |> elem(1)
      t2 = DateTime.from_iso8601("2026-10-23T10:01:00Z") |> elem(1)

      :ok =
        Repo.insert_check_result(conn, %Check.Result{
          node_id: "node-1",
          instance_id: "inst-1",
          peer_id: nil,
          kind: :interface_state,
          status: :ok,
          detail: "up",
          checked_at: t1,
          last_success_at: t1
        })

      :ok =
        Repo.insert_check_result(conn, %Check.Result{
          node_id: "node-1",
          instance_id: "inst-1",
          peer_id: nil,
          kind: :interface_state,
          status: :error,
          detail: "down",
          checked_at: t2,
          last_success_at: t1
        })

      [latest] = Repo.list_latest_check_results(conn)
      assert latest.node_id == "node-1"
      assert latest.instance_id == "inst-1"
      assert latest.kind == :interface_state
      assert latest.status == :error
      assert latest.checked_at == t2
      assert latest.last_success_at == t1
    end

    test "filters latest results by node_id and instance_id" do
      assert {:ok, conn} = Repo.open(":memory:")
      assert :ok = Repo.migrate(conn)

      :ok = Repo.insert_node(conn, sample_node("node-1"))
      :ok = Repo.insert_node(conn, sample_node("node-2"))

      t = DateTime.utc_now()

      :ok =
        Repo.insert_check_result(conn, %Check.Result{
          node_id: "node-1",
          instance_id: "inst-1",
          peer_id: nil,
          kind: :interface_state,
          status: :ok,
          detail: "up",
          checked_at: t,
          last_success_at: t
        })

      :ok =
        Repo.insert_check_result(conn, %Check.Result{
          node_id: "node-2",
          instance_id: "inst-2",
          peer_id: nil,
          kind: :interface_state,
          status: :ok,
          detail: "up",
          checked_at: t,
          last_success_at: t
        })

      assert length(Repo.list_latest_check_results(conn, node_id: "node-1")) == 1

      assert Repo.list_latest_check_results(conn, instance_id: "inst-2")
             |> hd()
             |> Map.get(:node_id) == "node-2"
    end
  end

  describe "latest_successful_check/5" do
    test "returns checked_at of the latest ok result for the same key" do
      assert {:ok, conn} = Repo.open(":memory:")
      assert :ok = Repo.migrate(conn)

      :ok = Repo.insert_node(conn, sample_node("node-1"))

      t_ok = DateTime.from_iso8601("2026-10-23T10:00:00Z") |> elem(1)
      t_error = DateTime.from_iso8601("2026-10-23T10:01:00Z") |> elem(1)

      :ok =
        Repo.insert_check_result(conn, %Check.Result{
          node_id: "node-1",
          instance_id: "inst-1",
          peer_id: nil,
          kind: :interface_state,
          status: :ok,
          detail: "up",
          checked_at: t_ok,
          last_success_at: t_ok
        })

      :ok =
        Repo.insert_check_result(conn, %Check.Result{
          node_id: "node-1",
          instance_id: "inst-1",
          peer_id: nil,
          kind: :interface_state,
          status: :error,
          detail: "down",
          checked_at: t_error,
          last_success_at: t_ok
        })

      assert Repo.latest_successful_check(conn, "node-1", "inst-1", nil, :interface_state) == t_ok
    end

    test "returns nil when no successful result exists" do
      assert {:ok, conn} = Repo.open(":memory:")
      assert :ok = Repo.migrate(conn)

      :ok = Repo.insert_node(conn, sample_node("node-1"))

      t = DateTime.from_iso8601("2026-10-23T10:00:00Z") |> elem(1)

      :ok =
        Repo.insert_check_result(conn, %Check.Result{
          node_id: "node-1",
          instance_id: "inst-1",
          peer_id: nil,
          kind: :interface_state,
          status: :error,
          detail: "down",
          checked_at: t,
          last_success_at: nil
        })

      assert Repo.latest_successful_check(conn, "node-1", "inst-1", nil, :interface_state) == nil
    end
  end

  describe "node last_contact" do
    test "persists and reads last_contact" do
      assert {:ok, conn} = Repo.open(":memory:")
      assert :ok = Repo.migrate(conn)

      :ok = Repo.insert_node(conn, sample_node("node-1"))

      t = DateTime.from_iso8601("2026-10-23T10:00:00Z") |> elem(1)
      :ok = Repo.update_node_last_contact(conn, "node-1", t)
      assert Repo.get_node_last_contact(conn, "node-1") == t
    end

    test "returns nil when last_contact was never set" do
      assert {:ok, conn} = Repo.open(":memory:")
      assert :ok = Repo.migrate(conn)

      :ok = Repo.insert_node(conn, sample_node("node-1"))
      assert Repo.get_node_last_contact(conn, "node-1") == nil
    end
  end

  defp sample_node(id) do
    %Node{
      id: id,
      name: id,
      address: "193.233.91.130",
      role: :entry
    }
  end
end
