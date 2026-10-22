defmodule WGM.ConfigGenerator do
  @moduledoc """
  Генерация серверных и клиентских конфигов WireGuard и AmneziaWG.

  Формат AWG:
  - при выключенной маскировке (jc=0, jmin=0, jmax=0, s1=0, s2=0,
    H1–H4 = 0/off/0-0 или 1..4) конфиг полностью совместим с WG;
  - при включённой маскировке в [Interface] сервера пишутся только общие
    параметры (S1–S4, H1–H4, HeaderProtectionKey);
  - при включённой маскировке в [Interface] клиента пишутся общие параметры
    плюс клиентские (Jc/Jmin/Jmax, I1–I5);
  - в [Peer] для включённой маскировки пишется `AdvancedSecurity = on`.

  Перед генерацией AWG-конфига параметры валидируются; при ошибке
  возвращается `{:error, reason}`.
  """

  alias WGM.{Instance, Peer}
  alias WGM.AWGParamsValidator

  @type config_string :: String.t()

  @doc """
  Генерирует серверный конфиг инстанса для заданного списка пиров.

  Приватный ключ сервера передаётся явно, чтобы контроллер не генерировал
  конфиг с `nil`-ключом.
  """
  @spec generate_server_config(Instance.t(), [Peer.t()], String.t()) ::
          {:ok, config_string()} | {:error, String.t()}
  def generate_server_config(_instance, _peers, nil) do
    {:error, "Private key is required"}
  end

  def generate_server_config(instance, peers, private_key) do
    with :ok <- validate_instance(instance) do
      interface_lines =
        build_interface_lines(
          instance,
          private_key,
          instance.address,
          instance.listen_port,
          instance.dns,
          instance.mtu,
          &server_awg_lines/1
        )

      peer_blocks =
        Enum.map(peers, &build_peer_block(&1, &1.public_key, nil, awg_security?(instance)))

      {:ok, Enum.join([interface_lines | peer_blocks], "\n") <> "\n"}
    end
  end

  @doc """
  Генерирует клиентский конфиг для одного пира.
  """
  @spec generate_client_config(Instance.t(), Peer.t(), String.t()) ::
          {:ok, config_string()} | {:error, String.t()}
  def generate_client_config(instance, peer, endpoint) do
    with :ok <- validate_instance(instance) do
      interface_lines =
        build_interface_lines(
          instance,
          peer.private_key,
          peer.address,
          nil,
          peer.dns,
          nil,
          &client_awg_lines/1
        )

      peer_block = build_peer_block(peer, instance.public_key, endpoint, awg_security?(instance))

      {:ok, Enum.join([interface_lines, peer_block], "\n") <> "\n"}
    end
  end

  defp validate_instance(%Instance{protocol: :awg, awg_params: nil}),
    do: {:error, "AWG params are required for AWG instances"}

  defp validate_instance(%Instance{protocol: :awg} = instance),
    do: AWGParamsValidator.validate(instance.awg_params)

  defp validate_instance(%Instance{protocol: :wg}), do: :ok

  defp build_interface_lines(instance, private_key, address, listen_port, dns, mtu, awg_lines_fn) do
    base = [
      "[Interface]",
      "PrivateKey = #{private_key}",
      "Address = #{address}"
    ]

    base = if listen_port, do: base ++ ["ListenPort = #{listen_port}"], else: base
    base = if dns, do: base ++ ["DNS = #{dns}"], else: base
    base = if mtu, do: base ++ ["MTU = #{mtu}"], else: base

    base =
      if instance.protocol == :awg and
           not AWGParamsValidator.masking_disabled?(instance.awg_params) do
        base ++ awg_lines_fn.(instance.awg_params)
      else
        base
      end

    Enum.join(base, "\n")
  end

  defp build_peer_block(%Peer{} = peer, public_key, endpoint, awg_security) do
    lines = [
      "",
      "[Peer]",
      "PublicKey = #{public_key}"
    ]

    lines =
      if peer.preshared_key,
        do: lines ++ ["PresharedKey = #{peer.preshared_key}"],
        else: lines

    lines = lines ++ ["AllowedIPs = #{peer.allowed_ips}"]

    lines =
      if endpoint,
        do: lines ++ ["Endpoint = #{endpoint}"],
        else: lines

    lines =
      if peer.persistent_keepalive && peer.persistent_keepalive != "off",
        do: lines ++ ["PersistentKeepalive = #{peer.persistent_keepalive}"],
        else: lines

    lines =
      if awg_security,
        do: lines ++ ["AdvancedSecurity = on"],
        else: lines

    Enum.join(lines, "\n")
  end

  defp server_awg_lines(%Instance.AWGParams{} = params) do
    s_h_lines(params) ++ header_protection_line(params)
  end

  defp client_awg_lines(%Instance.AWGParams{} = params) do
    [
      "Jc = #{params.jc}",
      "Jmin = #{params.jmin}",
      "Jmax = #{params.jmax}"
    ] ++
      s_h_lines(params) ++
      [
        "I1 = #{params.i1}",
        "I2 = #{params.i2}",
        "I3 = #{params.i3}",
        "I4 = #{params.i4}",
        "I5 = #{params.i5}"
      ] ++ header_protection_line(params)
  end

  # S1–S4 и H1–H4 общие для серверного и клиентского AWG-конфига.
  defp s_h_lines(%Instance.AWGParams{} = params) do
    [
      "S1 = #{params.s1}",
      "S2 = #{params.s2}",
      "S3 = #{params.s3}",
      "S4 = #{params.s4}",
      "H1 = #{params.h1}",
      "H2 = #{params.h2}",
      "H3 = #{params.h3}",
      "H4 = #{params.h4}"
    ]
  end

  defp header_protection_line(%Instance.AWGParams{header_protection_key: key})
       when key in [nil, "(none)"],
       do: []

  defp header_protection_line(%Instance.AWGParams{} = params),
    do: ["HeaderProtectionKey = #{params.header_protection_key}"]

  defp awg_security?(%Instance{protocol: :awg} = instance),
    do: not AWGParamsValidator.masking_disabled?(instance.awg_params)

  defp awg_security?(%Instance{protocol: :wg}), do: false

  @quick_keys [
    "Address",
    "DNS",
    "MTU",
    "Table",
    "PreUp",
    "PostUp",
    "PreDown",
    "PostDown",
    "SaveConfig"
  ]

  @doc """
  Убирает из конфига ключи, которые понимает только `wg-quick`/`awg-quick`,
  оставляя содержимое, пригодное для `wg setconf`/`wg syncconf`.

  Эквивалент `wg-quick strip <interface>`, но работает с конфигами в любом
  пути (в т.ч. `/etc/wireguard/wgm/`).
  """
  @spec strip_quick_keys(config_string()) :: config_string()
  def strip_quick_keys(config) do
    config
    |> String.split("\n", trim: false)
    |> Enum.reject(fn line ->
      trimmed = String.trim(line)

      Enum.any?(@quick_keys, fn key ->
        String.starts_with?(trimmed, "#{key} =") or trimmed == "#{key}"
      end)
    end)
    |> Enum.join("\n")
    |> normalize_empty_lines()
  end

  defp normalize_empty_lines(config) do
    config
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end
end
