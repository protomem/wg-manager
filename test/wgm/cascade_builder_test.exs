defmodule WGM.CascadeBuilderTest do
  use ExUnit.Case

  alias WGM.{Cascade, Instance, Node}

  defp entry_node do
    %Node{id: "entry-node", name: "entry", address: "193.233.91.130", role: :entry}
  end

  defp exit_node do
    %Node{id: "exit-node", name: "exit", address: "5.129.219.31", role: :exit}
  end

  describe "plan_instances/3" do
    test "returns AWG instance attrs for entry transit and exit" do
      plan = Cascade.Builder.plan_instances(entry_node(), exit_node())

      assert %{entry_transit: entry_attrs, exit: exit_attrs} = plan

      assert entry_attrs.node_id == "entry-node"
      assert entry_attrs.protocol == :awg
      assert entry_attrs.listen_port == 52_001
      assert entry_attrs.subnet == "10.200.0.0/30"
      assert entry_attrs.address == "10.200.0.1/30"

      assert exit_attrs.node_id == "exit-node"
      assert exit_attrs.protocol == :awg
      assert exit_attrs.listen_port == 52_002
      assert exit_attrs.subnet == "10.200.1.0/24"
      assert exit_attrs.address == "10.200.1.1/24"
    end

    test "exit instance includes NAT and ip_forward PostUp/PostDown" do
      plan = Cascade.Builder.plan_instances(entry_node(), exit_node())

      assert plan.exit.post_up == [
               "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE",
               "sysctl -w net.ipv4.ip_forward=1"
             ]

      assert plan.exit.post_down == [
               "iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
             ]
    end

    test "allows overriding defaults" do
      plan =
        Cascade.Builder.plan_instances(entry_node(), exit_node(),
          entry_transit_id: "et-1",
          entry_transit_name: "awg-entry",
          exit_id: "ex-1",
          exit_name: "awg-exit",
          nat_interface: "ens3"
        )

      assert plan.entry_transit.id == "et-1"
      assert plan.entry_transit.name == "awg-entry"
      assert plan.exit.id == "ex-1"
      assert plan.exit.name == "awg-exit"
      assert Enum.any?(plan.exit.post_up, &String.contains?(&1, "ens3"))
    end
  end

  describe "plan_instances/3 routing policy" do
    test "entry transit uses Table = off and selective policy rules" do
      plan =
        Cascade.Builder.plan_instances(entry_node(), exit_node(), client_subnet: "10.210.0.0/24")

      assert plan.entry_transit.table == "off"

      assert plan.entry_transit.post_up == [
               "ip rule add from 10.210.0.0/24 lookup 52001",
               "ip route add default dev %i table 52001"
             ]

      assert plan.entry_transit.pre_down == [
               "ip rule del from 10.210.0.0/24 lookup 52001",
               "ip route del default dev %i table 52001"
             ]
    end
  end

  describe "peer_attrs/4" do
    test "returns peer attrs linking entry transit to exit instance" do
      entry_wg = %Instance{
        id: "entry-wg",
        node_id: "entry-node",
        name: "wg-laptop",
        protocol: :wg,
        listen_port: 52_810,
        subnet: "10.210.0.0/24",
        public_key: "pub-wg",
        address: "10.210.0.1/24"
      }

      entry_transit = %Instance{
        id: "et-1",
        node_id: "entry-node",
        name: "awg-entry",
        protocol: :awg,
        listen_port: 52_001,
        subnet: "10.200.0.0/30",
        public_key: "pub-et",
        address: "10.200.0.1/30"
      }

      exit_instance = %Instance{
        id: "ex-1",
        node_id: "exit-node",
        name: "awg-exit",
        protocol: :awg,
        listen_port: 52_002,
        subnet: "10.200.1.0/24",
        public_key: "pub-ex",
        address: "10.200.1.1/24"
      }

      peers = Cascade.Builder.peer_attrs(entry_wg, entry_transit, exit_instance, exit_node())

      assert peers.entry_peer.public_key == "pub-ex"
      assert peers.entry_peer.allowed_ips == "0.0.0.0/0"
      assert peers.entry_peer.endpoint == "5.129.219.31:52002"
      assert peers.entry_peer.persistent_keepalive == 25

      assert peers.exit_peer.public_key == "pub-et"
      assert peers.exit_peer.allowed_ips == "10.210.0.0/24,10.200.0.1/32"
    end
  end
end
