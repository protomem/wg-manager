defmodule WGM.Agent do
  @moduledoc """
  Read-only агент узла. Хранит описание узла и список инстансов,
  по запросу возвращает структурированный статус через `WGM.Agent.Observer`.
  """

  use GenServer

  alias WGM.Agent.{Observer, Status}

  defstruct [:node, :instances, :adapter]

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

  @impl true
  def init(opts) do
    state = %__MODULE__{
      node: opts[:node],
      instances: opts[:instances] || [],
      adapter: opts[:adapter] || WGM.CLI.SystemAdapter
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = Observer.observe(state.node, state.instances, state.adapter)
    {:reply, status, state}
  end
end
