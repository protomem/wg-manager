defmodule WGM.Agent.KeyStore.FileSystemTest do
  use ExUnit.Case

  alias WGM.Agent.KeyStore.FileSystem

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    old_env = Application.get_env(:wgm, FileSystem)

    Application.put_env(:wgm, FileSystem, base_dir: %{"wg" => tmp_dir, "awg" => tmp_dir})

    on_exit(fn ->
      if old_env do
        Application.put_env(:wgm, FileSystem, old_env)
      else
        Application.delete_env(:wgm, FileSystem)
      end
    end)

    :ok
  end

  test "returns the default path for WG and AWG keys", %{tmp_dir: tmp_dir} do
    assert FileSystem.server_private_key_path(:wg, "inst-1") ==
             Path.join([tmp_dir, "wgm", "inst-1", "private_key"])

    assert FileSystem.server_private_key_path(:awg, "inst-2") ==
             Path.join([tmp_dir, "wgm", "inst-2", "private_key"])
  end

  test "writes and reads a private key with restricted permissions", %{tmp_dir: tmp_dir} do
    assert :ok = FileSystem.write_private_key(:wg, "inst-1", "secret-key")

    path = Path.join([tmp_dir, "wgm", "inst-1", "private_key"])
    assert File.read!(path) == "secret-key"

    assert FileSystem.read_private_key(:wg, "inst-1") == {:ok, "secret-key"}

    %{mode: mode} = File.stat!(path)
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "returns error when the key has not been written" do
    assert FileSystem.read_private_key(:wg, "missing") ==
             {:error, :enoent}
  end
end
