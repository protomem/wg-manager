defmodule WGM.Controller.AgentAdapter do
  @moduledoc """
  Behaviour-шов для подключения контроллера к агентам на узлах.
  """

  alias WGM.Node

  @doc """
  Запрашивает статус агента на узле.
  """
  @callback status(Node.t()) :: {:ok, WGM.Agent.Status.t()} | {:error, String.t()}
end
