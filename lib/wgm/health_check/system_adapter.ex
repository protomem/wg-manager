defmodule WGM.HealthCheck.SystemAdapter do
  @moduledoc """
  Реализация активных проверок через системные утилиты.

  `ping/1` использует системный `ping`; `end_to_end/1` пока не реализована
  до среза 9 (каскад) и возвращает ошибку с пояснением.
  """

  @behaviour WGM.HealthCheck.Adapter

  @impl true
  def ping(target) do
    case System.cmd("ping", ["-c", "1", "-W", "2", target], stderr_to_stdout: true) do
      {_output, 0} -> {:ok, "ping #{target} ok"}
      {output, _} -> {:error, "ping #{target} failed: #{String.trim(output)}"}
    end
  end

  @impl true
  def end_to_end(_route) do
    {:error, "end-to-end check requires cascade configuration (slice 9)"}
  end
end
