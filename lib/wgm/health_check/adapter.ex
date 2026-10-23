defmodule WGM.HealthCheck.Adapter do
  @moduledoc """
  Behaviour-шов для активных проверок доступности.
  """

  @type target :: String.t()
  @type route :: [String.t()]

  @doc """
  Выполняет ICMP-ping до `target`.
  """
  @callback ping(target()) :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Выполняет сквозную проверку по маршруту `route`.
  """
  @callback end_to_end(route()) :: {:ok, String.t()} | {:error, String.t()}
end
