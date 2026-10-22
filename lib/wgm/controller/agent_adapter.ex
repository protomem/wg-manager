defmodule WGM.Controller.AgentAdapter do
  @moduledoc """
  Behaviour-шов для подключения контроллера к агентам на узлах.
  """

  alias WGM.Node

  @doc """
  Запрашивает статус агента на узле.
  """
  @callback status(Node.t()) :: {:ok, WGM.Agent.Status.t()} | {:error, String.t()}

  @doc """
  Просит агента узла сгенерировать серверную ключевую пару для инстанса.

  Агент хранит приватный ключ локально и возвращает только публичный ключ.
  """
  @callback generate_keypair(Node.t(), instance_id :: String.t(), WGM.CLI.Adapter.protocol()) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc """
  Просит агента узла применить желаемое состояние инстанса (converge).
  """
  @callback apply_instance(
              Node.t(),
              WGM.Instance.t(),
              [WGM.Peer.t()],
              keyword()
            ) ::
              {:ok, map()} | {:error, String.t()}
end
