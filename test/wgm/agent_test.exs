defmodule WGM.AgentTest do
  use ExUnit.Case

  alias WGM.{Agent, Agent.Observer, Agent.Status, CLI.FakeAdapter, Instance, Node}

  setup do
    FakeAdapter.start()
    :ok
  end

  describe "Agent.status/1" do
    test "returns observed status via GenServer" do
      node = %Node{id: "node-gs", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-gs",
        node_id: "node-gs",
        name: "wggs",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.10.0.1/24"
      }

      dump = "priv\tpub\t51830\toff\n"
      FakeAdapter.set_dump(:wg, "wggs", dump)
      FakeAdapter.set_interface_state("wggs", :up)

      {:ok, agent} = Agent.start_link(node: node, instances: [instance], adapter: FakeAdapter)

      status = Agent.status(agent)
      assert status.node_id == "node-gs"
      assert [%Status.InstanceStatus{name: "wggs", interface_state: :up}] = status.instances
    end
  end

  describe "Observer.observe/3" do
    test "returns structured status for a single WG instance" do
      node = %Node{id: "node-1", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-wg-1",
        node_id: "node-1",
        name: "wg1",
        protocol: :wg,
        listen_port: 51820,
        subnet: "10.0.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.0.0.1/24"
      }

      dump =
        "priv\tpub\t51820\toff\n" <>
          "peer-pub\t\t192.168.1.2:1234\t10.0.0.2/32\t1699013400\t1024\t2048\t25\n"

      FakeAdapter.set_dump(:wg, "wg1", dump)
      FakeAdapter.set_interface_state("wg1", :up)

      status = Observer.observe(node, [instance], FakeAdapter)

      assert status.node_id == "node-1"
      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.instance_id == "inst-wg-1"
      assert inst_status.name == "wg1"
      assert inst_status.protocol == :wg
      assert inst_status.interface_state == :up
      assert inst_status.present
      assert inst_status.device.public_key == "pub"
      assert inst_status.device.listen_port == 51820
      assert [peer] = inst_status.peers
      assert peer.public_key == "peer-pub"
      assert peer.transfer_rx == 1024
      assert inst_status.error == nil
    end

    test "returns structured status for an AWG instance" do
      node = %Node{id: "node-2", name: "exit", address: "185.40.31.22", role: :exit}

      instance = %Instance{
        id: "inst-awg-1",
        node_id: "node-2",
        name: "awg1",
        protocol: :awg,
        listen_port: 51821,
        subnet: "10.1.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.1.0.1/24"
      }

      dump =
        "priv\tpub\t51821\t" <>
          "3\t40\t100\t1\t2\t3\t4\t5\t6\t7\t8\t" <>
          "1\t2\t3\t4\t5\thpk\toff\n" <>
          "peer-pub\t\t192.168.1.3:1234\t10.1.0.2/32\t1699013400\t4096\t8192\t0-0\n"

      FakeAdapter.set_dump(:awg, "awg1", dump)
      FakeAdapter.set_interface_state("awg1", :up)

      status = Observer.observe(node, [instance], FakeAdapter)

      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.protocol == :awg
      assert inst_status.interface_state == :up
      assert inst_status.present
      assert inst_status.device.awg_params.jc == 3
      assert inst_status.device.awg_params.header_protection_key == "hpk"
      assert [peer] = inst_status.peers
      assert peer.persistent_keepalive == "0-0"
      assert inst_status.error == nil
    end

    test "reports interface down when the adapter returns :down" do
      node = %Node{id: "node-1", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-wg-down",
        node_id: "node-1",
        name: "wg2",
        protocol: :wg,
        listen_port: 51822,
        subnet: "10.2.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.2.0.1/24"
      }

      dump = "priv\tpub\t51822\toff\n"
      FakeAdapter.set_dump(:wg, "wg2", dump)
      FakeAdapter.set_interface_state("wg2", :down)

      status = Observer.observe(node, [instance], FakeAdapter)

      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.interface_state == :down
      assert inst_status.present
      assert inst_status.error == nil
    end

    test "reports present when interface state query fails but dump succeeds" do
      node = %Node{id: "node-1", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-missing-state",
        node_id: "node-1",
        name: "missingstate0",
        protocol: :wg,
        listen_port: 51823,
        subnet: "10.3.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.3.0.1/24"
      }

      dump = "priv\tpub\t51823\toff\n"
      FakeAdapter.set_dump(:wg, "missingstate0", dump)

      status = Observer.observe(node, [instance], FakeAdapter)

      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.present
      assert inst_status.interface_state == :unknown
      assert inst_status.error =~ "Interface missingstate0 not found"
      assert inst_status.device.public_key == "pub"
    end

    test "reports not present when both interface state and dump queries fail" do
      node = %Node{id: "node-1", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-missing",
        node_id: "node-1",
        name: "missing0",
        protocol: :wg,
        listen_port: 51823,
        subnet: "10.3.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.3.0.1/24"
      }

      status = Observer.observe(node, [instance], FakeAdapter)

      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.present == false
      assert inst_status.interface_state == :unknown
      assert inst_status.error =~ "Interface missing0 not found"
    end

    test "returns status for multiple instances" do
      node = %Node{id: "node-multi", name: "entry", address: "193.233.91.130", role: :entry}

      wg = %Instance{
        id: "inst-wg-multi",
        node_id: "node-multi",
        name: "wg10",
        protocol: :wg,
        listen_port: 51840,
        subnet: "10.10.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.10.0.1/24"
      }

      awg = %Instance{
        id: "inst-awg-multi",
        node_id: "node-multi",
        name: "awg10",
        protocol: :awg,
        listen_port: 51841,
        subnet: "10.11.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.11.0.1/24"
      }

      FakeAdapter.set_dump(:wg, "wg10", "priv\tpub\t51840\toff\n")

      FakeAdapter.set_dump(
        :awg,
        "awg10",
        "priv\tpub\t51841\t" <> String.duplicate("0\t", 16) <> "0\tfw\n"
      )

      FakeAdapter.set_interface_state("wg10", :up)
      FakeAdapter.set_interface_state("awg10", :up)

      status = Observer.observe(node, [wg, awg], FakeAdapter)

      assert length(status.instances) == 2
      assert Enum.any?(status.instances, &(&1.protocol == :wg and &1.interface_state == :up))
      assert Enum.any?(status.instances, &(&1.protocol == :awg and &1.interface_state == :up))
    end

    test "reports not present and error when dump parse fails but interface exists" do
      node = %Node{id: "node-1", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-dump-error",
        node_id: "node-1",
        name: "wg3",
        protocol: :wg,
        listen_port: 51824,
        subnet: "10.4.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.4.0.1/24"
      }

      FakeAdapter.set_interface_state("wg3", :up)
      FakeAdapter.set_dump(:wg, "wg3", "")

      status = Observer.observe(node, [instance], FakeAdapter)

      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.present == false
      assert inst_status.interface_state == :up
      assert inst_status.error == "Empty dump"
    end
  end
end
