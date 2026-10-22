defmodule WGM.Application do
  @moduledoc """
  OTP-приложение WGM.

  Режим запуска выбирается через application env `:wgm, :mode` или
  переменную окружения `WGM_MODE`:

    - `:agent` — на узле запускается `WGM.Agent` под именем `:wgm_agent`;
    - `:controller` — запускается `WGM.Controller` под именем `:wgm_controller`;
    - любое другое значение — приложение стартует без дочерних процессов
      (полезно для тестов и интерактивных сессий).

  Параметры агента (`WGM_NODE_*`) и контроллера (`WGM_DB_PATH`) читаются
  из переменных окружения в релизе.
  """

  use Application

  alias WGM.{Agent, Controller, Instance, Node}

  @default_db_path "/var/lib/wgm/controller.db"

  @impl true
  def start(_type, _args) do
    children = children()
    opts = [strategy: :one_for_one, name: WGM.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Возвращает дочерние спецификации для текущего режима.
  """
  @spec children() :: [Supervisor.child_spec()]
  def children do
    case mode() do
      :agent -> agent_children()
      :controller -> controller_children()
      _ -> []
    end
  end

  @doc """
  Разбирает строковое значение режима в атом.

  Поддерживаются только `"agent"` и `"controller"`; всё остальное
  трактуется как `nil`.
  """
  @spec parse_mode(String.t() | nil) :: :agent | :controller | nil
  def parse_mode("agent"), do: :agent
  def parse_mode("controller"), do: :controller
  def parse_mode(_), do: nil

  @doc """
  Определяет текущий режим работы.

  Переменная окружения `WGM_MODE` имеет приоритет над application env.
  """
  @spec mode() :: :agent | :controller | nil
  def mode do
    parse_mode(System.get_env("WGM_MODE")) || Application.get_env(:wgm, :mode)
  end

  defp agent_children do
    node = build_node()
    instances = agent_instances()

    [
      {Agent, node: node, instances: instances, read_only: agent_read_only(), name: :wgm_agent}
    ]
  end

  defp agent_instances do
    case System.get_env("WGM_AGENT_INSTANCES") do
      nil -> []
      "" -> []
      value -> parse_instances(value)
    end
  end

  # Формат: id:protocol:name:listen_port:subnet:address[:target_state]|...
  # protocol — wg или awg; listen_port/subnet/address могут быть произвольными,
  # так как read-only агент использует только name и protocol для наблюдения.
  # target_state — configured (по умолчанию), up, down.
  defp parse_instances(value) do
    value
    |> String.split("|")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_instance/1)
  end

  defp parse_instance(raw) do
    parts = String.split(raw, ":")

    [id, protocol, name, port, subnet, address] = Enum.take(parts, 6)
    target_state = Enum.at(parts, 6, "configured")

    %Instance{
      id: id,
      node_id: System.get_env("WGM_NODE_ID", ""),
      name: name,
      protocol: parse_protocol(protocol),
      listen_port: String.to_integer(port),
      subnet: subnet,
      private_key: nil,
      public_key: nil,
      address: address,
      target_state: parse_target_state(target_state)
    }
  end

  defp parse_protocol("wg"), do: :wg
  defp parse_protocol("awg"), do: :awg

  defp parse_protocol(other),
    do: raise("Unknown protocol in WGM_AGENT_INSTANCES: #{other} (expected wg or awg)")

  defp parse_target_state("up"), do: :up
  defp parse_target_state("down"), do: :down
  defp parse_target_state(_), do: :configured

  defp controller_children do
    db_path = System.get_env("WGM_DB_PATH", @default_db_path)

    [
      {Controller, db_path: db_path, name: :wgm_controller}
    ]
  end

  defp build_node do
    %Node{
      id: fetch_env!("WGM_NODE_ID"),
      name: fetch_env!("WGM_NODE_NAME"),
      address: fetch_env!("WGM_NODE_ADDRESS"),
      role: parse_role(System.get_env("WGM_NODE_ROLE")),
      description: System.get_env("WGM_NODE_DESCRIPTION")
    }
  end

  defp fetch_env!(name) do
    case System.fetch_env(name) do
      {:ok, value} -> value
      :error -> raise "Missing required environment variable: #{name}"
    end
  end

  defp parse_role("entry"), do: :entry
  defp parse_role("exit"), do: :exit
  defp parse_role(_), do: :standalone

  defp agent_read_only do
    case System.get_env("WGM_AGENT_READ_ONLY") do
      "false" -> false
      "0" -> false
      _ -> true
    end
  end
end
