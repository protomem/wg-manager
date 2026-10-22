defmodule WGM.Agent.ConfigStore.FileSystem do
  @moduledoc """
  Реализация хранилища конфигов инстансов через файловую систему.

  Базовые каталоги:
    - `/etc/wireguard/wgm` для WG;
    - `/etc/amnezia/amneziawg/wgm` для AWG.

  Бэкапы хранятся рядом с конфигом в виде `<name>.conf.backup.<timestamp>`.
  Сохраняются не более `max_backups` (по умолчанию 5) последних бэкапов.
  """

  @behaviour WGM.Agent.ConfigStore

  @default_base_dirs %{"wg" => "/etc/wireguard/wgm", "awg" => "/etc/amnezia/amneziawg/wgm"}
  @default_max_backups 5

  @impl true
  def config_path(protocol, instance_name) do
    Path.join([base_dir(protocol), "#{instance_name}.conf"])
  end

  @impl true
  def read_config(protocol, instance_name) do
    protocol
    |> config_path(instance_name)
    |> File.read()
    |> case do
      {:ok, content} -> {:ok, content}
      error -> error
    end
  end

  @impl true
  def write_config(protocol, instance_name, content) do
    path = config_path(protocol, instance_name)
    tmp = "#{path}.tmp"
    dir = Path.dirname(path)

    with :ok <- ensure_dir(dir),
         :ok <- File.write(tmp, content),
         :ok <- File.chmod(tmp, 0o600),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @impl true
  def backup_config(protocol, instance_name) do
    path = config_path(protocol, instance_name)

    case File.exists?(path) do
      true ->
        backup_path = "#{path}.backup.#{timestamp()}"

        with :ok <- File.rename(path, backup_path) do
          rotate_backups(path)
        else
          {:error, reason} -> {:error, inspect(reason)}
        end

      false ->
        :ok
    end
  end

  @impl true
  def delete_config(protocol, instance_name) do
    protocol
    |> config_path(instance_name)
    |> File.rm()
    |> case do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
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
        :ok

      error ->
        error
    end
  end

  defp rotate_backups(path) do
    max =
      Application.get_env(:wgm, __MODULE__, []) |> Keyword.get(:max_backups, @default_max_backups)

    dir = Path.dirname(path)
    prefix = "#{Path.basename(path)}.backup."

    backups =
      dir
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.sort(:desc)

    case Enum.drop(backups, max) do
      [] ->
        :ok

      to_remove ->
        Enum.each(to_remove, fn name -> File.rm(Path.join(dir, name)) end)
        :ok
    end
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601(:basic)
  end
end
