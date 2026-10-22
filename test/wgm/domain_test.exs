defmodule WGM.DomainTest do
  use ExUnit.Case

  alias WGM.{Node, Instance, Peer, Cascade}

  describe "Node" do
    test "creates a node with required fields" do
      node = %Node{
        id: "node-1",
        name: "entry",
        address: "193.233.91.130",
        role: :entry
      }

      assert node.id == "node-1"
      assert node.name == "entry"
      assert node.address == "193.233.91.130"
      assert node.role == :entry
    end

    test "supports all roles" do
      assert %Node{role: :entry}.role == :entry
      assert %Node{role: :exit}.role == :exit
      assert %Node{role: :standalone}.role == :standalone
    end
  end

  describe "Instance" do
    test "creates a WG instance" do
      instance = %Instance{
        id: "inst-1",
        node_id: "node-1",
        name: "wg-entry",
        protocol: :wg,
        listen_port: 51820,
        subnet: "10.0.0.0/24",
        private_key: "server-private-key",
        public_key: "server-public-key",
        address: "10.0.0.1/24"
      }

      assert instance.protocol == :wg
      assert instance.listen_port == 51820
      assert instance.awg_params == nil
    end

    test "creates an AWG instance with params" do
      awg_params = %Instance.AWGParams{
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

      instance = %Instance{
        id: "inst-2",
        node_id: "node-1",
        name: "awg-exit",
        protocol: :awg,
        listen_port: 51821,
        subnet: "10.0.1.0/24",
        private_key: "server-private-key",
        public_key: "server-public-key",
        address: "10.0.1.1/24",
        awg_params: awg_params
      }

      assert instance.protocol == :awg
      assert instance.awg_params.jc == 5
    end
  end

  describe "Peer" do
    test "creates a peer" do
      peer = %Peer{
        id: "peer-1",
        instance_id: "inst-1",
        name: "laptop",
        private_key: "peer-private-key",
        public_key: "peer-public-key",
        preshared_key: "peer-preshared-key",
        allowed_ips: "0.0.0.0/0",
        persistent_keepalive: 25,
        address: "10.0.0.2/24"
      }

      assert peer.name == "laptop"
      assert peer.allowed_ips == "0.0.0.0/0"
      assert peer.persistent_keepalive == 25
    end
  end

  describe "Cascade" do
    test "creates a cascade" do
      cascade = %Cascade{
        id: "cascade-1",
        entry_instance_id: "inst-entry",
        exit_instance_id: "inst-exit"
      }

      assert cascade.entry_instance_id == "inst-entry"
      assert cascade.exit_instance_id == "inst-exit"
    end
  end
end
