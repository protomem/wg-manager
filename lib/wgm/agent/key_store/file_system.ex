defmodule WGM.Agent.KeyStore.FileSystem do
  @moduledoc """
  Реализация хранилища приватных ключей серверных инстансов через файловую
  систему.

  Ключи хранятся в:
    - `/etc/wireguard/wgm/<instance_id>/private_key` для WG;
    - `/etc/amnezia/amneziawg/wgm/<instance_id>/private_key` для AWG.

  Права: файл `0600`, каталог инстанса `0700`.

  Базовый каталог можно переопределить через application env для тестов:
      Application.put_env(:wgm, __MODULE__, base_dir: %{"wg" => "/tmp/wgm-wg", "awg" => "/tmp/wgm-awg"})
  """

  @behaviour WGM.Agent.KeyStore

  @default_base_dirs %{"wg" => "/etc/wireguard", "awg" => "/etc/amnezia/amneziawg"}

  @impl true
  def server_private_key_path(protocol, instance_id) do
    Path.join([base_dir(protocol), "wgm", instance_id, "private_key"])
  end

  @impl true
  def read_private_key(protocol, instance_id) do
    protocol
    |> server_private_key_path(instance_id)
    |> File.read()
    |> case do
      {:ok, key} -> {:ok, String.trim(key)}
      error -> error
    end
  end

  @impl true
  def write_private_key(protocol, instance_id, key) do
    path = server_private_key_path(protocol, instance_id)
    dir = Path.dirname(path)

    with :ok <- ensure_dir(dir),
         :ok <- File.write(path, key),
         :ok <- File.chmod(path, 0o600) do
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
      error -> {:error, inspect(error)}
    end
  end

  defp base_dir(protocol) do
    env = Application.get_env(:wgm, __MODULE__, [])

    env
    |> Keyword.get(:base_dir, @default_base_dirs)
    |> Map.fetch!(to_string(protocol))
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok ->
        _ = File.chmod(dir, 0o700)
        _ = File.chmod(Path.dirname(dir), 0o700)
        :ok

      error ->
        error
    end
  end
end
