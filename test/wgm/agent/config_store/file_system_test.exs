defmodule WGM.Agent.ConfigStore.FileSystemTest do
  use ExUnit.Case

  alias WGM.Agent.ConfigStore.FileSystem

  setup do
    dir = Path.join(System.tmp_dir!(), "wgm-config-store-#{:erlang.unique_integer([:positive])}")
    Application.put_env(:wgm, FileSystem, base_dir: %{"wg" => dir, "awg" => dir})

    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  test "config_path returns wg path" do
    assert FileSystem.config_path(:wg, "wg1") =~ "/wg1.conf"
  end

  test "write_config creates file atomically and sets 0600 permissions", %{dir: dir} do
    :ok = FileSystem.write_config(:wg, "wg1", "[Interface]\nPrivateKey = x\n")

    path = Path.join(dir, "wg1.conf")
    assert File.exists?(path)
    refute File.exists?("#{path}.tmp")
    assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
  end

  test "read_config returns content" do
    :ok = FileSystem.write_config(:wg, "wg1", "content\n")
    assert FileSystem.read_config(:wg, "wg1") == {:ok, "content\n"}
  end

  test "backup_config rotates and keeps up to max_backups", %{dir: dir} do
    :ok = FileSystem.write_config(:wg, "wg1", "v1\n")
    :ok = FileSystem.backup_config(:wg, "wg1")
    :ok = FileSystem.write_config(:wg, "wg1", "v2\n")
    :ok = FileSystem.backup_config(:wg, "wg1")

    backups =
      dir
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, "wg1.conf.backup."))

    assert length(backups) == 2
  end

  test "delete_config removes the file" do
    :ok = FileSystem.write_config(:wg, "wg1", "content\n")
    :ok = FileSystem.delete_config(:wg, "wg1")
    assert FileSystem.read_config(:wg, "wg1") == {:error, :enoent}
  end
end
