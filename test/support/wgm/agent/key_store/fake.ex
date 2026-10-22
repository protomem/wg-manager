defmodule WGM.Agent.KeyStore.Fake do
  @moduledoc """
  Фейк-хранилище приватных ключей серверных инстансов для тестов.

  Хранит ключи в именованной ETS-таблице.
  """

  @behaviour WGM.Agent.KeyStore

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

  @spec set_private_key(WGM.CLI.Adapter.protocol(), String.t(), String.t()) :: :ok
  def set_private_key(protocol, instance_id, key) do
    :ets.insert(__MODULE__, {{:key, protocol, instance_id}, key})
    :ok
  end

  @impl true
  def server_private_key_path(protocol, instance_id) do
    "/fake/#{protocol}/#{instance_id}/private_key"
  end

  @impl true
  def read_private_key(protocol, instance_id) do
    case :ets.lookup(__MODULE__, {:key, protocol, instance_id}) do
      [{_, key}] -> {:ok, key}
      [] -> {:error, :enoent}
    end
  end

  @impl true
  def write_private_key(protocol, instance_id, key) do
    set_private_key(protocol, instance_id, key)
  end
end
