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

  @impl true
  def show_dump(protocol, interface) do
    with {:ok, output} <- run_command(bin(protocol), ["show", "all", "dump"]) do
      filtered =
        output
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, interface <> "\t"))
        |> Enum.map(&strip_interface_column/1)
        |> Enum.join("\n")

      if filtered == "" do
        {:error, "Interface #{interface} not found in dump"}
      else
        {:ok, filtered}
      end
    end
  end

  defp strip_interface_column(line) do
    case String.split(line, "\t", parts: 2) do
      [_interface, rest] -> rest
      _ -> line
    end
  end

  @impl true
  def interface_state(interface) do
    run_command("ip", ["link", "show", interface], &parse_interface_state/1)
  end

  @impl true
  def syncconf(protocol, interface, config_path) do
    run_command(bin(protocol), ["syncconf", interface, config_path], fn _ -> :ok end)
  end

  @impl true
  def strip_config(_protocol, _interface, config_path) do
    case File.read(config_path) do
      {:ok, content} -> {:ok, WGM.ConfigGenerator.strip_quick_keys(content)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @impl true
  def up(protocol, _interface, config_path) do
    quick_bin = quick_bin(protocol)
    run_command(quick_bin, ["up", config_path], fn _ -> :ok end)
  end

  @impl true
  def down(protocol, _interface, config_path) do
    quick_bin = quick_bin(protocol)
    run_command(quick_bin, ["down", config_path], fn _ -> :ok end)
  end

  defp parse_interface_state(output) do
    flags = interface_flags(output)

    cond do
      String.contains?(flags, "UP") -> {:ok, :up}
      String.contains?(output, "state DOWN") -> {:ok, :down}
      flags != "" -> {:ok, :down}
      true -> {:ok, :unknown}
    end
  end

  defp interface_flags(output) do
    case Regex.run(~r/<([^>]*)>/, output) do
      [_, flags] -> flags
      nil -> ""
    end
  end

  defp bin(:wg), do: "wg"
  defp bin(:awg), do: "awg"

  defp quick_bin(:wg), do: "wg-quick"
  defp quick_bin(:awg), do: "awg-quick"

  defp run_command(cmd, args, output_handler \\ &{:ok, String.trim(&1)}) do
    case safe_cmd(cmd, args, []) do
      {:ok, {output, 0}} -> output_handler.(output)
      {:ok, {output, _}} -> {:error, String.trim(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_command_with_input(cmd, args, input) do
    case safe_cmd(cmd, args, stdin: input) do
      {:ok, {output, 0}} -> {:ok, String.trim(output)}
      {:ok, {output, _}} -> {:error, String.trim(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_cmd(cmd, args, opts) do
    try do
      {:ok, System.cmd(cmd, args, [stderr_to_stdout: true] ++ opts)}
    rescue
      e in ErlangError ->
        {:error, command_error_reason(cmd, e)}
    end
  end

  defp command_error_reason(cmd, %ErlangError{original: reason}) do
    case reason do
      :enoent -> "Command not found: #{cmd}"
      _ -> "Failed to run #{cmd}: #{inspect(reason)}"
    end
  end
end
