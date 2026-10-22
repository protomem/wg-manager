defmodule WGM.Controller.RepoTest do
  use ExUnit.Case

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
end
