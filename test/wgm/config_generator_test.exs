defmodule WGM.ConfigGeneratorTest do
  use ExUnit.Case

  alias WGM.{Instance, Peer}
  alias WGM.ConfigGenerator

  describe "generate_server_config/2" do
    test "generates WG server config" do
      instance = wg_instance()
      peer = wg_server_peer()

      assert {:ok, config} = ConfigGenerator.generate_server_config(instance, [peer])

      assert config == ~s"""
             [Interface]
             PrivateKey = server-private-key
             Address = 10.0.0.1/24
             ListenPort = 51820
             DNS = 1.1.1.1
             MTU = 1420

             [Peer]
             PublicKey = peer-public-key
             PresharedKey = peer-preshared-key
             AllowedIPs = 10.0.0.2/32
             PersistentKeepalive = 25
             """
    end

    test "generates AWG server config with shared params only" do
      instance = awg_instance()
      peer = awg_server_peer()

      assert {:ok, config} = ConfigGenerator.generate_server_config(instance, [peer])

      # Серверный конфиг содержит только общие параметры (S1–S4, H1–H4, HeaderProtectionKey).
      assert config == ~s"""
             [Interface]
             PrivateKey = server-private-key
             Address = 10.0.1.1/24
             ListenPort = 51821
             S1 = 100
             S2 = 200
             S3 = 300
             S4 = 400
             H1 = 1-10
             H2 = 11-20
             H3 = 21-30
             H4 = 31-40
             HeaderProtectionKey = hpk

             [Peer]
             PublicKey = peer-public-key
             PresharedKey = peer-preshared-key
             AllowedIPs = 10.0.1.2/32
             PersistentKeepalive = 25
             AdvancedSecurity = on
             """
    end

    test "returns error for invalid AWG params" do
      instance = %{awg_instance() | awg_params: %{awg_params() | jc: -1}}

      assert {:error, _msg} =
               ConfigGenerator.generate_server_config(instance, [awg_server_peer()])
    end

    test "generates WG-compatible AWG server config when masking disabled" do
      instance = %{awg_instance() | awg_params: disabled_awg_params()}
      peer = %{awg_server_peer() | persistent_keepalive: "off"}

      assert {:ok, config} = ConfigGenerator.generate_server_config(instance, [peer])

      assert config == ~s"""
             [Interface]
             PrivateKey = server-private-key
             Address = 10.0.1.1/24
             ListenPort = 51821

             [Peer]
             PublicKey = peer-public-key
             PresharedKey = peer-preshared-key
             AllowedIPs = 10.0.1.2/32
             """
    end
  end

  describe "generate_client_config/3" do
    test "generates WG client config" do
      instance = wg_instance()
      peer = wg_client_peer()

      assert {:ok, config} =
               ConfigGenerator.generate_client_config(instance, peer, "193.233.91.130:51820")

      assert config == ~s"""
             [Interface]
             PrivateKey = peer-private-key
             Address = 10.0.0.2/24
             DNS = 1.1.1.1

             [Peer]
             PublicKey = server-public-key
             PresharedKey = peer-preshared-key
             AllowedIPs = 0.0.0.0/0
             Endpoint = 193.233.91.130:51820
             PersistentKeepalive = 25
             """
    end

    test "generates AWG client config with client-side params" do
      instance = awg_instance()
      peer = awg_client_peer()

      assert {:ok, config} =
               ConfigGenerator.generate_client_config(instance, peer, "193.233.91.130:51821")

      assert config == ~s"""
             [Interface]
             PrivateKey = peer-private-key
             Address = 10.0.1.2/24
             DNS = 1.1.1.1
             Jc = 5
             Jmin = 50
             Jmax = 100
             S1 = 100
             S2 = 200
             S3 = 300
             S4 = 400
             H1 = 1-10
             H2 = 11-20
             H3 = 21-30
             H4 = 31-40
             I1 = 1
             I2 = 2
             I3 = 3
             I4 = 4
             I5 = 5
             HeaderProtectionKey = hpk

             [Peer]
             PublicKey = server-public-key
             PresharedKey = peer-preshared-key
             AllowedIPs = 0.0.0.0/0
             Endpoint = 193.233.91.130:51821
             PersistentKeepalive = 25
             AdvancedSecurity = on
             """
    end

    test "returns error for invalid AWG params" do
      instance = %{awg_instance() | awg_params: %{awg_params() | jc: 129}}

      assert {:error, _msg} =
               ConfigGenerator.generate_client_config(
                 instance,
                 awg_client_peer(),
                 "193.233.91.130:51821"
               )
    end

    test "generates WG-compatible AWG client config when masking disabled" do
      instance = %{awg_instance() | awg_params: disabled_awg_params()}
      peer = %{awg_client_peer() | persistent_keepalive: "off"}

      assert {:ok, config} =
               ConfigGenerator.generate_client_config(instance, peer, "193.233.91.130:51821")

      assert config == ~s"""
             [Interface]
             PrivateKey = peer-private-key
             Address = 10.0.1.2/24
             DNS = 1.1.1.1

             [Peer]
             PublicKey = server-public-key
             PresharedKey = peer-preshared-key
             AllowedIPs = 0.0.0.0/0
             Endpoint = 193.233.91.130:51821
             """
    end
  end

  defp wg_instance do
    %Instance{
      id: "inst-1",
      node_id: "node-1",
      name: "wg-entry",
      protocol: :wg,
      listen_port: 51820,
      subnet: "10.0.0.0/24",
      private_key: "server-private-key",
      public_key: "server-public-key",
      address: "10.0.0.1/24",
      dns: "1.1.1.1",
      mtu: 1420
    }
  end

  defp wg_server_peer do
    %Peer{
      id: "peer-1",
      instance_id: "inst-1",
      name: "laptop",
      private_key: "peer-private-key",
      public_key: "peer-public-key",
      preshared_key: "peer-preshared-key",
      allowed_ips: "10.0.0.2/32",
      persistent_keepalive: 25,
      address: "10.0.0.2/24"
    }
  end

  defp wg_client_peer do
    %Peer{
      id: "peer-1",
      instance_id: "inst-1",
      name: "laptop",
      private_key: "peer-private-key",
      public_key: "peer-public-key",
      preshared_key: "peer-preshared-key",
      allowed_ips: "0.0.0.0/0",
      persistent_keepalive: 25,
      address: "10.0.0.2/24",
      dns: "1.1.1.1"
    }
  end

  defp awg_instance do
    %Instance{
      id: "inst-2",
      node_id: "node-1",
      name: "awg-exit",
      protocol: :awg,
      listen_port: 51821,
      subnet: "10.0.1.0/24",
      private_key: "server-private-key",
      public_key: "server-public-key",
      address: "10.0.1.1/24",
      awg_params: awg_params()
    }
  end

  defp awg_server_peer do
    %Peer{
      id: "peer-2",
      instance_id: "inst-2",
      name: "cascade-peer",
      private_key: "peer-private-key",
      public_key: "peer-public-key",
      preshared_key: "peer-preshared-key",
      allowed_ips: "10.0.1.2/32",
      persistent_keepalive: 25,
      address: "10.0.1.2/24"
    }
  end

  defp awg_client_peer do
    %Peer{
      id: "peer-2",
      instance_id: "inst-2",
      name: "cascade-peer",
      private_key: "peer-private-key",
      public_key: "peer-public-key",
      preshared_key: "peer-preshared-key",
      allowed_ips: "0.0.0.0/0",
      persistent_keepalive: 25,
      address: "10.0.1.2/24",
      dns: "1.1.1.1"
    }
  end

  defp awg_params do
    %Instance.AWGParams{
      jc: 5,
      jmin: 50,
      jmax: 100,
      s1: 100,
      s2: 200,
      s3: 300,
      s4: 400,
      h1: "1-10",
      h2: "11-20",
      h3: "21-30",
      h4: "31-40",
      i1: 1,
      i2: 2,
      i3: 3,
      i4: 4,
      i5: 5,
      header_protection_key: "hpk"
    }
  end

  defp disabled_awg_params do
    %Instance.AWGParams{
      jc: 0,
      jmin: 0,
      jmax: 0,
      s1: 0,
      s2: 0,
      s3: 0,
      s4: 0,
      h1: "1",
      h2: "2",
      h3: "3",
      h4: "4",
      i1: 0,
      i2: 0,
      i3: 0,
      i4: 0,
      i5: 0,
      header_protection_key: nil
    }
  end
end
