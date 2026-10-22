defmodule WGM.Agent do
  @moduledoc """
  Read-only агент узла. Хранит описание узла и список инстансов,
  по запросу возвращает структурированный статус через `WGM.Agent.Observer`.
  """

  use GenServer

  alias WGM.Agent.{Observer, Status}
  alias WGM.CLI.Adapter

  defstruct [:node, :instances, :adapter, server_keys: %{}]

  @doc """
  Запускает агента.

  Опции:
    - `:node` — `%WGM.Node{}`;
    - `:instances` — список `%WGM.Instance{}`;
    - `:adapter` — модуль, реализующая `WGM.CLI.Adapter` (по умолчанию
      `WGM.CLI.SystemAdapter`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Возвращает текущий статус узла.
  """
  @spec status(GenServer.server()) :: Status.t()
  def status(agent) do
    GenServer.call(agent, :status)
  end

  @doc """
  Генерирует серверную ключевую пару для инстанса.

  Приватный ключ сохраняется локально в состоянии агента, возвращается
  только публичный ключ.
  """
  @spec generate_keypair(GenServer.server(), String.t(), Adapter.protocol()) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_keypair(agent, instance_id, protocol) do
    GenServer.call(agent, {:generate_keypair, instance_id, protocol})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      node: opts[:node],
      instances: opts[:instances] || [],
      adapter: opts[:adapter] || WGM.CLI.SystemAdapter,
      server_keys: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = Observer.observe(state.node, state.instances, state.adapter)
    {:reply, status, state}
  end

  def handle_call({:generate_keypair, instance_id, protocol}, _from, state) do
    case generate_keypair_on_node(state.adapter, protocol) do
      {:ok, private_key, public_key} ->
        new_state = %{state | server_keys: Map.put(state.server_keys, instance_id, private_key)}
        {:reply, {:ok, public_key}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp generate_keypair_on_node(adapter, protocol) do
    with {:ok, private_key} <- adapter.genkey(protocol),
         {:ok, public_key} <- adapter.pubkey(private_key, protocol) do
      {:ok, private_key, public_key}
    end
  end
end
