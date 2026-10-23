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
  def end_to_end(%{interface: interface, source_ip: source_ip, target: target}) do
    with :ok <- check_interface_up(interface),
         :ok <- check_handshake(interface),
         :ok <- ping_through(interface, source_ip, target) do
      {:ok, "end-to-end through #{interface} to #{target} ok"}
    end
  end

  def end_to_end(_route) do
    {:error, "end-to-end check requires %{interface: ..., source_ip: ..., target: ...}"}
  end

  defp check_interface_up(interface) do
    case System.cmd("ip", ["link", "show", "dev", interface], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "state UP") do
          :ok
        else
          {:error, "interface #{interface} is not up"}
        end

      {output, _} ->
        {:error, "interface #{interface} not found: #{String.trim(output)}"}
    end
  end

  defp check_handshake(interface) do
    case System.cmd("wg", ["show", interface, "latest-handshakes"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, _} ->
        {:error, "no handshake on #{interface}: #{String.trim(output)}"}
    end
  end

  defp ping_through(interface, source_ip, target) do
    args = ["-I", interface, "-S", source_ip, "-c", "1", "-W", "2", target]

    case System.cmd("ping", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _} -> {:error, "ping through #{interface} failed: #{String.trim(output)}"}
    end
  end
end
