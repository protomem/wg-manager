defmodule WGM.Parser do
  @moduledoc """
  Парсеры вывода `wg show dump` и `awg show dump`.

  Формат WG (TAB-разделитель):
  - строка устройства: private-key, public-key, listen-port, fwmark
  - строки пиров: public-key, preshared-key, endpoint, allowed-ips,
    latest-handshake, transfer-rx, transfer-tx, persistent-keepalive

  Формат AWG: тот же базовый набор, но строка устройства содержит
  дополнительные колонки параметров маскировки (Jc, Jmin, Jmax, S1–S4,
  H1–H4, I1–I5, HeaderProtectionKey и возможно другие), а fwmark — последняя.
  PersistentKeepalive у пира — строка-диапазон или `off`.
  """

  alias WGM.Instance.AWGParams

  @type peer_status :: %{
          public_key: String.t(),
          preshared_key: String.t(),
          endpoint: String.t(),
          allowed_ips: String.t(),
          latest_handshake: integer(),
          transfer_rx: integer(),
          transfer_tx: integer(),
          persistent_keepalive: String.t() | integer()
        }

  @type wg_status :: %{
          private_key: String.t(),
          public_key: String.t(),
          listen_port: integer(),
          fwmark: String.t(),
          peers: [peer_status()]
        }

  @type awg_status :: %{
          private_key: String.t(),
          public_key: String.t(),
          listen_port: integer(),
          fwmark: String.t(),
          awg_params: AWGParams.t(),
          peers: [peer_status()]
        }

  @doc """
  Парсит вывод `wg show dump`.
  """
  @spec parse_wg_show_dump(String.t()) :: {:ok, wg_status()} | {:error, String.t()}
  def parse_wg_show_dump(dump) do
    parse_dump(dump, &parse_wg_device/1, :wg)
  end

  @doc """
  Парсит вывод `awg show dump`.
  """
  @spec parse_awg_show_dump(String.t()) :: {:ok, awg_status()} | {:error, String.t()}
  def parse_awg_show_dump(dump) do
    parse_dump(dump, &parse_awg_device/1, :awg)
  end

  defp parse_dump(dump, device_parser, protocol) do
    lines = normalize_lines(dump)

    case lines do
      [device_line | peer_lines] ->
        with {:ok, device} <- device_parser.(device_line),
             {:ok, peers} <- parse_peers(peer_lines, protocol) do
          {:ok, Map.put(device, :peers, peers)}
        end

      _ ->
        {:error, "Empty dump"}
    end
  end

  defp normalize_lines(dump) do
    dump
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_wg_device(line) do
    cols = String.split(line, "\t")

    if length(cols) != 4 do
      {:error, "Invalid WG device line: expected 4 columns, got #{length(cols)}"}
    else
      [private_key, public_key, listen_port_str, fwmark] = cols

      with {listen_port, ""} <- Integer.parse(listen_port_str) do
        {:ok,
         %{
           private_key: private_key,
           public_key: public_key,
           listen_port: listen_port,
           fwmark: fwmark
         }}
      else
        _ -> {:error, "Invalid listen port in WG device line"}
      end
    end
  end

  defp parse_awg_device(line) do
    cols = String.split(line, "\t")

    # Минимум: 3 базовые колонки + 16 обязательных AWG-параметров + fwmark.
    # Некоторые версии awg добавляют ещё header_protection_key (21-я колонка).
    min_cols = 3 + 16 + 1

    if length(cols) < min_cols do
      {:error,
       "Invalid AWG device line: expected at least #{min_cols} columns, got #{length(cols)}"}
    else
      [private_key, public_key, listen_port_str | rest] = cols

      with {listen_port, ""} <- Integer.parse(listen_port_str),
           {:ok, awg_params, fwmark} <- parse_awg_device_params(rest) do
        {:ok,
         %{
           private_key: private_key,
           public_key: public_key,
           listen_port: listen_port,
           fwmark: fwmark,
           awg_params: awg_params
         }}
      else
        _ -> {:error, "Invalid AWG device line"}
      end
    end
  end

  defp parse_awg_device_params(cols) do
    # Последняя колонка — fwmark, перед ней — AWG-параметры.
    # Поддерживаем 16 обязательных параметров и опциональный header_protection_key.
    case Enum.split(cols, -1) do
      {awg_cols, [fwmark]} when length(awg_cols) >= 16 ->
        parse_known_awg_params(awg_cols, fwmark)

      _ ->
        {:error, "Invalid AWG device line: expected at least 16 parameter columns before fwmark"}
    end
  end

  defp parse_known_awg_params(awg_cols, fwmark) do
    [
      jc_str,
      jmin_str,
      jmax_str,
      s1_str,
      s2_str,
      s3_str,
      s4_str,
      h1,
      h2,
      h3,
      h4,
      i1_str,
      i2_str,
      i3_str,
      i4_str,
      i5_str
      | extras
    ] = awg_cols

    header_protection_key = List.first(extras)

    with {jc, ""} <- Integer.parse(jc_str),
         {jmin, ""} <- Integer.parse(jmin_str),
         {jmax, ""} <- Integer.parse(jmax_str),
         {s1, ""} <- Integer.parse(s1_str),
         {s2, ""} <- Integer.parse(s2_str),
         {s3, ""} <- Integer.parse(s3_str),
         {s4, ""} <- Integer.parse(s4_str),
         i1 <- parse_int_or_nil(i1_str),
         i2 <- parse_int_or_nil(i2_str),
         i3 <- parse_int_or_nil(i3_str),
         i4 <- parse_int_or_nil(i4_str),
         i5 <- parse_int_or_nil(i5_str) do
      {:ok,
       %AWGParams{
         jc: jc,
         jmin: jmin,
         jmax: jmax,
         s1: s1,
         s2: s2,
         s3: s3,
         s4: s4,
         h1: h1,
         h2: h2,
         h3: h3,
         h4: h4,
         i1: i1,
         i2: i2,
         i3: i3,
         i4: i4,
         i5: i5,
         header_protection_key: header_protection_key
       }, fwmark}
    else
      _ -> {:error, "Invalid AWG parameter value"}
    end
  end

  defp parse_peers(peer_lines, protocol) do
    peer_lines
    |> Enum.map(&parse_peer_line(protocol, &1))
    |> Enum.reduce({:ok, []}, fn
      {:ok, peer}, {:ok, peers} -> {:ok, [peer | peers]}
      {:error, _} = err, _acc -> err
      _, {:error, _} = err -> err
    end)
    |> case do
      {:ok, peers} -> {:ok, Enum.reverse(peers)}
      err -> err
    end
  end

  defp parse_peer_line(protocol, line) do
    cols = String.split(line, "\t")

    if length(cols) != 8 do
      {:error, "Invalid peer line: expected 8 columns, got #{length(cols)}"}
    else
      [
        public_key,
        preshared_key,
        endpoint,
        allowed_ips,
        latest_handshake_str,
        transfer_rx_str,
        transfer_tx_str,
        persistent_keepalive_str
      ] = cols

      persistent_keepalive =
        if protocol == :wg do
          parse_int_or_zero(persistent_keepalive_str)
        else
          persistent_keepalive_str
        end

      {:ok,
       %{
         public_key: public_key,
         preshared_key: preshared_key,
         endpoint: endpoint,
         allowed_ips: allowed_ips,
         latest_handshake: parse_int_or_zero(latest_handshake_str),
         transfer_rx: parse_int_or_zero(transfer_rx_str),
         transfer_tx: parse_int_or_zero(transfer_tx_str),
         persistent_keepalive: persistent_keepalive
       }}
    end
  end

  defp parse_int_or_zero(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp parse_int_or_nil("(null)"), do: nil

  defp parse_int_or_nil(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
