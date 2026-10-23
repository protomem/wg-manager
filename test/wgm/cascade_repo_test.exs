defmodule WGM.CascadeRepoTest do
  use ExUnit.Case

  alias WGM.{Cascade, Controller.Repo, Instance, Node}

  setup do
    {:ok, conn} = Repo.open(":memory:")
    :ok = Repo.migrate(conn)
    {:ok, conn: conn}
  end

  defp insert_node(conn, id, role) do
    :ok =
      Repo.insert_node(conn, %Node{
        id: id,
        name: id,
        address: "127.0.0.1",
        role: role
      })
  end

  defp insert_instance(conn, id, node_id, protocol \\ :wg) do
    :ok =
      Repo.insert_instance(conn, %Instance{
        id: id,
        node_id: node_id,
        name: id,
        protocol: protocol,
        listen_port: 51820,
        subnet: "10.0.0.0/24",
        public_key: "pub-#{id}",
        address: "10.0.0.1/24",
        target_state: :configured
      })
  end

  describe "cascade CRUD" do
    test "inserts and retrieves a cascade", %{conn: conn} do
      insert_node(conn, "entry-node", :entry)
      insert_node(conn, "exit-node", :exit)
      insert_instance(conn, "entry-inst", "entry-node")
      insert_instance(conn, "exit-inst", "exit-node")

      cascade = %Cascade{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst",
        name: "main"
      }

      assert :ok = Repo.insert_cascade(conn, cascade)
      assert %Cascade{id: "cascade-1"} = Repo.get_cascade(conn, "cascade-1")

      assert [%Cascade{id: "cascade-1"}] = Repo.list_cascades(conn)
    end

    test "deletes a cascade", %{conn: conn} do
      insert_node(conn, "entry-node", :entry)
      insert_node(conn, "exit-node", :exit)
      insert_instance(conn, "entry-inst", "entry-node")
      insert_instance(conn, "exit-inst", "exit-node")

      cascade = %Cascade{
        id: "cascade-1",
        entry_instance_id: "entry-inst",
        exit_instance_id: "exit-inst"
      }

      :ok = Repo.insert_cascade(conn, cascade)
      assert :ok = Repo.delete_cascade(conn, "cascade-1")
      assert Repo.get_cascade(conn, "cascade-1") == nil
      assert Repo.list_cascades(conn) == []
    end
  end
end
