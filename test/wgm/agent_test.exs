defmodule WGM.AgentTest do
  use ExUnit.Case

  alias WGM.{Agent, Agent.Observer, Agent.Status, CLI.FakeAdapter, Instance, Node}
  alias WGM.Agent.ConfigStore.Fake, as: FakeConfigStore
  alias WGM.Agent.KeyStore.Fake, as: FakeKeyStore

  setup do
    FakeAdapter.start()
    FakeKeyStore.start()
    FakeConfigStore.start()
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

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [instance],
          adapter: FakeAdapter,
          key_store: FakeKeyStore
        )

      status = Agent.status(agent)
      assert status.node_id == "node-gs"
      assert [%Status.InstanceStatus{name: "wggs", interface_state: :up}] = status.instances
    end
  end

  describe "Agent.generate_keypair/3" do
    test "returns a public key and stores the private key on the agent" do
      node = %Node{id: "node-kg", name: "entry", address: "193.233.91.130", role: :entry}

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          read_only: false
        )

      assert {:ok, "public-for-private-key-1"} =
               Agent.generate_keypair(agent, "inst-kg", :wg)
    end

    test "returns different keys for different instances" do
      node = %Node{id: "node-kg", name: "entry", address: "193.233.91.130", role: :entry}

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          read_only: false
        )

      assert {:ok, pub1} = Agent.generate_keypair(agent, "inst-1", :wg)
      assert {:ok, pub2} = Agent.generate_keypair(agent, "inst-2", :wg)
      refute pub1 == pub2
    end

    test "persists the private key and returns the same public key on repeated calls" do
      node = %Node{id: "node-persist", name: "entry", address: "193.233.91.130", role: :entry}

      {:ok, agent1} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          read_only: false
        )

      assert {:ok, pub1} = Agent.generate_keypair(agent1, "inst-persist", :wg)

      {:ok, agent2} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          read_only: false
        )

      assert {:ok, pub2} = Agent.generate_keypair(agent2, "inst-persist", :wg)
      assert pub1 == pub2

      assert FakeKeyStore.read_private_key(:wg, "inst-persist") ==
               {:ok, "private-key-1"}
    end

    test "refuses to generate keys in read-only mode" do
      node = %Node{id: "node-ro", name: "entry", address: "193.233.91.130", role: :entry}

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          read_only: true
        )

      assert {:error, "read-only mode"} = Agent.generate_keypair(agent, "inst-ro", :wg)
      assert FakeKeyStore.read_private_key(:wg, "inst-ro") == {:error, :enoent}
    end
  end

  describe "Agent.apply_instance/4" do
    test "applies converge when not in read-only mode" do
      node = %Node{id: "node-apply", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-apply",
        node_id: "node-apply",
        name: "wgapply",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.10.0.1/24"
      }

      FakeKeyStore.set_private_key(:wg, "inst-apply", "priv")
      FakeAdapter.set_dump(:wg, "wgapply", "priv\tpub\t51830\toff\n")
      FakeAdapter.set_interface_state("wgapply", :up)

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: false
        )

      assert {:ok, %{action: :up, changed: true}} =
               Agent.apply_instance(agent, instance, [], action: :up)

      assert {:ok, config} = FakeConfigStore.read_config(:wg, "wgapply")
      assert config =~ "PrivateKey = priv"
    end

    test "refuses to apply in read-only mode" do
      node = %Node{id: "node-ro-apply", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-ro-apply",
        node_id: "node-ro-apply",
        name: "wgro",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.10.0.1/24"
      }

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: true
        )

      assert {:error, "read-only mode"} = Agent.apply_instance(agent, instance, [], action: :up)
    end

    test "updates state.instances after apply" do
      node = %Node{id: "node-state", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-state",
        node_id: "node-state",
        name: "wgstate",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.10.0.1/24",
        target_state: :configured
      }

      FakeKeyStore.set_private_key(:wg, "inst-state", "priv")
      FakeAdapter.set_dump(:wg, "wgstate", "priv\tpub\t51830\toff\n")
      FakeAdapter.set_interface_state("wgstate", :up)

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [instance],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: false
        )

      assert {:ok, %{action: :up, changed: true}} =
               Agent.apply_instance(agent, instance, [], action: :up)

      status = Agent.status(agent)
      assert [%{instance_id: "inst-state", interface_state: :up}] = status.instances

      FakeAdapter.set_dump(:wg, "wgstate", "")

      assert {:ok, %{action: :down, changed: true}} =
               Agent.apply_instance(agent, instance, [], action: :down, confirm: true)

      # wg-quick down удаляет интерфейс; наблюдение видит отсутствие.
      status = Agent.status(agent)
      assert [%{instance_id: "inst-state", interface_state: :unknown}] = status.instances

      assert {:ok, %{action: :absent, changed: true}} =
               Agent.apply_instance(agent, instance, [], action: :absent, confirm: true)

      status = Agent.status(agent)

      # Инстанс удалён из state.instances — наблюдение его больше не видит.
      assert status.instances == []
    end

    test "adds new instance to state.instances after apply" do
      node = %Node{id: "node-new", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-new",
        node_id: "node-new",
        name: "wgnew",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.10.0.1/24",
        target_state: :configured
      }

      FakeKeyStore.set_private_key(:wg, "inst-new", "priv")
      FakeAdapter.set_dump(:wg, "wgnew", "priv\tpub\t51830\toff\n")
      FakeAdapter.set_interface_state("wgnew", :up)

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: false
        )

      assert {:ok, %{action: :up, changed: true}} =
               Agent.apply_instance(agent, instance, [], action: :up)

      status = Agent.status(agent)
      assert [%{instance_id: "inst-new", interface_state: :up}] = status.instances
    end

    test "does not add instance to state.instances on dry run" do
      node = %Node{id: "node-dry", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-dry",
        node_id: "node-dry",
        name: "wgdry",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.0.0.1/24",
        target_state: :configured
      }

      FakeKeyStore.set_private_key(:wg, "inst-dry", "priv")
      FakeAdapter.set_dump(:wg, "wgdry", "priv\tpub\t51830\toff\n")
      FakeAdapter.set_interface_state("wgdry", :up)

      {:ok, agent} =
        Agent.start_link(
          node: node,
          instances: [],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: false
        )

      assert {:ok, %{action: :up, dry_run: true, changed: true}} =
               Agent.apply_instance(agent, instance, [], action: :up, dry_run: true)

      status = Agent.status(agent)
      assert status.instances == []
    end

    test "applies saved configs at boot for instances with target_state :up" do
      node = %Node{id: "node-boot", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-boot",
        node_id: "node-boot",
        name: "wgboot",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.10.0.1/24",
        target_state: :up
      }

      FakeConfigStore.set_config(:wg, "wgboot", "[Interface]\nPrivateKey = priv\n")

      {:ok, _agent} =
        Agent.start_link(
          node: node,
          instances: [instance],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: false
        )

      assert [{:up, :wg, "wgboot", "/fake/wg/wgboot.conf"}] = FakeAdapter.calls()
    end

    test "skips interfaces already up at boot" do
      node = %Node{id: "node-boot-up", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-boot-up",
        node_id: "node-boot-up",
        name: "wgbootup",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.10.0.1/24",
        target_state: :up
      }

      FakeConfigStore.set_config(:wg, "wgbootup", "[Interface]\nPrivateKey = priv\n")
      FakeAdapter.set_interface_state("wgbootup", :up)

      {:ok, _agent} =
        Agent.start_link(
          node: node,
          instances: [instance],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: false
        )

      assert FakeAdapter.calls() == []
    end

    test "does not apply configs at boot in read-only mode" do
      node = %Node{id: "node-ro-boot", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-ro-boot",
        node_id: "node-ro-boot",
        name: "wgroboot",
        protocol: :wg,
        listen_port: 51830,
        subnet: "10.10.0.0/24",
        private_key: nil,
        public_key: "pub",
        address: "10.10.0.1/24",
        target_state: :up
      }

      FakeConfigStore.set_config(:wg, "wgroboot", "[Interface]\nPrivateKey = priv\n")

      {:ok, _agent} =
        Agent.start_link(
          node: node,
          instances: [instance],
          adapter: FakeAdapter,
          key_store: FakeKeyStore,
          config_store: FakeConfigStore,
          read_only: true
        )

      assert FakeAdapter.calls() == []
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

    test "does not expose private keys in device status for WG" do
      node = %Node{id: "node-1", name: "entry", address: "193.233.91.130", role: :entry}

      instance = %Instance{
        id: "inst-wg-private",
        node_id: "node-1",
        name: "wg-private",
        protocol: :wg,
        listen_port: 51820,
        subnet: "10.0.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.0.0.1/24"
      }

      FakeAdapter.set_dump(:wg, "wg-private", "real-private-key\tpub\t51820\toff\n")
      FakeAdapter.set_interface_state("wg-private", :up)

      status = Observer.observe(node, [instance], FakeAdapter)

      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.present
      assert inst_status.device.private_key == nil
      assert inst_status.device.public_key == "pub"
    end

    test "does not expose private keys in device status for AWG" do
      node = %Node{id: "node-2", name: "exit", address: "185.40.31.22", role: :exit}

      instance = %Instance{
        id: "inst-awg-private",
        node_id: "node-2",
        name: "awg-private",
        protocol: :awg,
        listen_port: 51821,
        subnet: "10.1.0.0/24",
        private_key: "priv",
        public_key: "pub",
        address: "10.1.0.1/24"
      }

      dump =
        "real-private-key\tpub\t51821\t" <>
          "3\t40\t100\t1\t2\t3\t4\t5\t6\t7\t8\t" <>
          "1\t2\t3\t4\t5\thpk\toff\n"

      FakeAdapter.set_dump(:awg, "awg-private", dump)
      FakeAdapter.set_interface_state("awg-private", :up)

      status = Observer.observe(node, [instance], FakeAdapter)

      assert [%Status.InstanceStatus{} = inst_status] = status.instances
      assert inst_status.present
      assert inst_status.device.private_key == nil
      assert inst_status.device.awg_params.header_protection_key == "hpk"
    end
  end
end
