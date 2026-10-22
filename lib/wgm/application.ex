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
  Определяет текущий режим работы.

  Переменная окружения `WGM_MODE` имеет приоритет над application env.
  """
  @spec mode() :: :agent | :controller | nil
  def mode do
    env_mode() || Application.get_env(:wgm, :mode)
  end

  defp env_mode do
    case System.get_env("WGM_MODE") do
      "agent" -> :agent
      "controller" -> :controller
      _ -> nil
    end
  end

  defp agent_children do
    node = build_node()
    instances = agent_instances()

    [
      {Agent, node: node, instances: instances, name: :wgm_agent}
    ]
  end

  defp agent_instances do
    case System.get_env("WGM_AGENT_INSTANCES") do
      nil -> []
      "" -> []
      value -> parse_instances(value)
    end
  end

  # Формат: id:protocol:name:listen_port:subnet:address|...
  # protocol — wg или awg; listen_port/subnet/address могут быть произвольными,
  # так как read-only агент использует только name и protocol для наблюдения.
  defp parse_instances(value) do
    value
    |> String.split("|")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_instance/1)
  end

  defp parse_instance(raw) do
    [id, protocol, name, port, subnet, address] = String.split(raw, ":")

    %Instance{
      id: id,
      node_id: System.get_env("WGM_NODE_ID", ""),
      name: name,
      protocol: String.to_atom(protocol),
      listen_port: String.to_integer(port),
      subnet: subnet,
      private_key: nil,
      public_key: "dummy",
      address: address
    }
  end

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
end
