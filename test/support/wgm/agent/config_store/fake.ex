defmodule WGM.Agent.ConfigStore.Fake do
  @moduledoc """
  Фейк-хранилище конфигов инстансов для тестов.

  Хранит конфиги в именованной ETS-таблице.
  """

  @behaviour WGM.Agent.ConfigStore

  @spec start() :: :ok
  def start do
    if :ets.whereis(__MODULE__) == :undefined do
      :ets.new(__MODULE__, [:public, :named_table, read_concurrency: true])
    else
      :ets.delete_all_objects(__MODULE__)
    end

    :ok
  end

  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(__MODULE__)
    :ok
  end

  @spec set_config(WGM.CLI.Adapter.protocol(), String.t(), String.t()) :: :ok
  def set_config(protocol, instance_name, content) do
    :ets.insert(__MODULE__, {{:config, protocol, instance_name}, content})
    :ok
  end

  @impl true
  def config_path(protocol, instance_name) do
    "/fake/#{protocol}/#{instance_name}.conf"
  end

  @impl true
  def read_config(protocol, instance_name) do
    case :ets.lookup(__MODULE__, {:config, protocol, instance_name}) do
      [{_, content}] -> {:ok, content}
      [] -> {:error, :enoent}
    end
  end

  @impl true
  def write_config(protocol, instance_name, content) do
    :ets.insert(__MODULE__, {{:config, protocol, instance_name}, content})
    :ok
  end

  @impl true
  def backup_config(protocol, instance_name) do
    case read_config(protocol, instance_name) do
      {:ok, content} ->
        backups =
          case :ets.lookup(__MODULE__, {:backups, protocol, instance_name}) do
            [{_, list}] -> list
            [] -> []
          end

        :ets.insert(
          __MODULE__,
          {{:backups, protocol, instance_name}, [content | backups]}
        )

        :ok

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @impl true
  def delete_config(protocol, instance_name) do
    :ets.delete(__MODULE__, {:config, protocol, instance_name})
    :ok
  end

  @spec backups(WGM.CLI.Adapter.protocol(), String.t()) :: [String.t()]
  def backups(protocol, instance_name) do
    case :ets.lookup(__MODULE__, {:backups, protocol, instance_name}) do
      [{_, list}] -> Enum.reverse(list)
      [] -> []
    end
  end

  @spec last_backup(WGM.CLI.Adapter.protocol(), String.t()) :: String.t() | nil
  def last_backup(protocol, instance_name) do
    case backups(protocol, instance_name) do
      [] -> nil
      list -> List.last(list)
    end
  end
end
