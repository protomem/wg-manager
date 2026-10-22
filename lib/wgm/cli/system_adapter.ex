defmodule WGM.CLI.SystemAdapter do
  @moduledoc """
  Реализация CLI-адаптера через System.cmd. Вызывает `wg` для протокола :wg
  и `awg` для протокола :awg.
  """

  @behaviour WGM.CLI.Adapter

  @impl true
  def genkey(protocol) do
    run_command(bin(protocol), ["genkey"])
  end

  @impl true
  def pubkey(private_key, protocol) do
    run_command_with_input(bin(protocol), ["pubkey"], private_key)
  end

  @impl true
  def genpsk do
    run_command("wg", ["genpsk"])
  end

  defp bin(:wg), do: "wg"
  defp bin(:awg), do: "awg"

  defp run_command(cmd, args) do
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp run_command_with_input(cmd, args, input) do
    case System.cmd(cmd, args, stdin: input, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end
end
