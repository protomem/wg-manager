defmodule WGM.ConfigGeneratorPostTest do
  use ExUnit.Case

  alias WGM.{ConfigGenerator, Instance, Peer}

  defp wg_instance(attrs \\ %{}) do
    %Instance{
      id: "inst-1",
      node_id: "node-1",
      name: "wg1",
      protocol: :wg,
      listen_port: 51820,
      subnet: "10.0.0.0/24",
      public_key: "server-pub",
      address: "10.0.0.1/24",
      target_state: :configured
    }
    |> Map.merge(attrs)
  end

  describe "PostUp/PostDown" do
    test "includes PostUp and PostDown lines in server config" do
      instance =
        wg_instance(%{
          post_up: [
            "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE",
            "sysctl -w net.ipv4.ip_forward=1"
          ],
          post_down: ["iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"]
        })

      peer = %Peer{
        id: "peer-1",
        instance_id: "inst-1",
        name: "laptop",
        private_key: "peer-priv",
        public_key: "peer-pub",
        allowed_ips: "10.0.0.2/32",
        address: "10.0.0.2/32"
      }

      {:ok, config} = ConfigGenerator.generate_server_config(instance, [peer], "server-priv")

      assert config =~ "PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
      assert config =~ "PostUp = sysctl -w net.ipv4.ip_forward=1"
      assert config =~ "PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
    end

    test "omits PostUp/PostDown when empty" do
      instance = wg_instance()

      {:ok, config} =
        ConfigGenerator.generate_server_config(instance, [], "server-priv")

      refute config =~ "PostUp"
      refute config =~ "PostDown"
    end

    test "strip_quick_keys removes PostUp/PostDown" do
      instance =
        wg_instance(%{
          post_up: ["sysctl -w net.ipv4.ip_forward=1"]
        })

      {:ok, config} = ConfigGenerator.generate_server_config(instance, [], "server-priv")
      stripped = ConfigGenerator.strip_quick_keys(config)

      refute stripped =~ "PostUp"
      assert stripped =~ "[Interface]"
      assert stripped =~ "PrivateKey"
    end
  end
end
