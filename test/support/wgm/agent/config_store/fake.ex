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
    notify_adapter_config_exists(protocol, instance_name, true)
    :ok
  end

  @spec set_delete_result(WGM.CLI.Adapter.protocol(), String.t(), :ok | {:error, String.t()}) ::
          :ok
  def set_delete_result(protocol, instance_name, result) do
    :ets.insert(__MODULE__, {{:delete_result, protocol, instance_name}, result})
    :ok
  end

  @spec set_backup_result(WGM.CLI.Adapter.protocol(), String.t(), :ok | {:error, String.t()}) ::
          :ok
  def set_backup_result(protocol, instance_name, result) do
    :ets.insert(__MODULE__, {{:backup_result, protocol, instance_name}, result})
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
    notify_adapter_config_exists(protocol, instance_name, true)
    :ok
  end

  @impl true
  def backup_config(protocol, instance_name) do
    case :ets.lookup(__MODULE__, {:backup_result, protocol, instance_name}) do
      [{_, result}] ->
        :ets.delete(__MODULE__, {:backup_result, protocol, instance_name})
        result

      [] ->
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
  end

  @impl true
  def delete_config(protocol, instance_name) do
    case :ets.lookup(__MODULE__, {:delete_result, protocol, instance_name}) do
      [{_, result}] ->
        :ets.delete(__MODULE__, {:delete_result, protocol, instance_name})
        result

      [] ->
        :ets.delete(__MODULE__, {:config, protocol, instance_name})
        notify_adapter_config_exists(protocol, instance_name, false)
        :ok
    end
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

  @doc """
  Returns true if a config is currently stored for the instance.

  Used by test fakes that model CLI-tool dependencies on the config file.
  """
  @spec config_exists?(WGM.CLI.Adapter.protocol(), String.t()) :: boolean()
  def config_exists?(protocol, instance_name) do
    case :ets.lookup(__MODULE__, {:config, protocol, instance_name}) do
      [{_, _content}] -> true
      [] -> false
    end
  end

  # Keep the CLI fake in sync so that `set_down_requires_existing_config/3`
  # reflects the current state of the config store.
  defp notify_adapter_config_exists(protocol, instance_name, exists) do
    if :ets.whereis(WGM.CLI.FakeAdapter) != :undefined do
      WGM.CLI.FakeAdapter.set_config_exists(protocol, instance_name, exists)
    end
  end
end
