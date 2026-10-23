defmodule WGM.Agent.ConvergerTest do
  use ExUnit.Case

  alias WGM.{Agent.Converger, CLI.FakeAdapter, Instance, Peer}
  alias WGM.Agent.ConfigStore.Fake, as: FakeConfigStore
  alias WGM.Agent.KeyStore.Fake, as: FakeKeyStore

  setup do
    FakeAdapter.start()
    FakeKeyStore.start()
    FakeConfigStore.start()
    :ok
  end

  describe "converge/4 :up" do
    test "creates interface with wg-quick up when interface is absent" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      # Интерфейс отсутствует (interface_state не задан → error → absent),
      # но dump уже заранее подготовлен для верификации после up.
      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))

      state = build_state()

      assert {:ok, %{action: :up, changed: true}} =
               Converger.converge(state, instance, [], action: :up)

      assert {:ok, config} = FakeConfigStore.read_config(:wg, "wg1")
      assert config =~ "[Interface]"
      assert config =~ "PrivateKey = server-private-key"
      assert config =~ "ListenPort = 51820"

      assert [{:up, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()
    end

    test "syncconfs with stripped config when interface exists" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))
      FakeAdapter.set_interface_state("wg1", :up)

      FakeAdapter.set_strip_content(
        :wg,
        "wg1",
        "[Interface]\nPrivateKey = server-private-key\nListenPort = 51820\n"
      )

      state = build_state()

      assert {:ok, %{action: :up, changed: true}} =
               Converger.converge(state, instance, [], action: :up)

      assert [{:strip_config, :wg, "wg1", "/fake/wg/wg1.conf"}, {:syncconf, :wg, "wg1", _}] =
               FakeAdapter.calls()
    end

    test "is idempotent when config did not change and interface exists" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))
      FakeAdapter.set_interface_state("wg1", :up)

      state = build_state()

      assert {:ok, %{action: :up, changed: true}} =
               Converger.converge(state, instance, [], action: :up)

      FakeAdapter.reset()
      FakeAdapter.set_interface_state("wg1", :up)

      assert {:ok, %{action: :up, changed: false}} =
               Converger.converge(state, instance, [], action: :up)

      assert FakeAdapter.calls() == []
    end

    test "returns error when private key is missing" do
      instance = build_instance("wg1", :wg)

      assert {:error, "Private key not found for instance inst-wg1"} =
               Converger.converge(build_state(), instance, [], action: :up)
    end

    test "rolls back when verification fails" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")
      FakeConfigStore.set_config(:wg, "wg1", "old-config\n")
      FakeAdapter.set_interface_state("wg1", :up)

      wrong_dump = "priv\twrong-pub\t51820\toff\n"
      FakeAdapter.set_dump(:wg, "wg1", wrong_dump)

      state = build_state()

      assert {:error, "Verification failed: Public key mismatch" <> _} =
               Converger.converge(state, instance, [], action: :up)

      assert FakeConfigStore.last_backup(:wg, "wg1") == "old-config\n"
      assert {:ok, "old-config\n"} = FakeConfigStore.read_config(:wg, "wg1")
    end
  end

  describe "converge/4 :down" do
    test "stops the interface when it is up" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")
      FakeConfigStore.set_config(:wg, "wg1", "old-config\n")

      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", "")

      state = build_state()

      assert {:ok, %{action: :down, changed: true}} =
               Converger.converge(state, instance, [], action: :down, confirm: true)

      assert [{:down, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()
      assert {:ok, "old-config\n"} = FakeConfigStore.read_config(:wg, "wg1")
    end

    test "succeeds verification after real down without rollback" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")
      FakeConfigStore.set_config(:wg, "wg1", "old-config\n")

      FakeAdapter.set_interface_state("wg1", :up)

      state = build_state()

      assert {:ok, %{action: :down, changed: true}} =
               Converger.converge(state, instance, [], action: :down, confirm: true)

      # Интерфейс удалён, конфиг на месте, rollback не вызывался.
      assert [{:down, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()
      assert {:ok, "old-config\n"} = FakeConfigStore.read_config(:wg, "wg1")
      assert FakeConfigStore.backups(:wg, "wg1") == []
    end

    test "is no-op when interface has already been removed" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      state = build_state()

      assert {:ok, %{action: :down, changed: false}} =
               Converger.converge(state, instance, [], action: :down)

      assert FakeAdapter.calls() == []
    end

    test "requires confirmation when interface is up" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")
      FakeAdapter.set_interface_state("wg1", :up)

      assert {:error, "Destructive action down requires confirmation"} =
               Converger.converge(build_state(), instance, [], action: :down)
    end
  end

  describe "converge/4 :restart" do
    test "downs existing interface and brings it back up" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))
      FakeAdapter.set_interface_state("wg1", :up)

      state = build_state()

      assert {:ok, %{action: :restart, changed: true}} =
               Converger.converge(state, instance, [], action: :restart, confirm: true)

      assert [down_call, up_call] = FakeAdapter.calls()
      assert down_call == {:down, :wg, "wg1", "/fake/wg/wg1.conf"}
      assert up_call == {:up, :wg, "wg1", "/fake/wg/wg1.conf"}
    end

    test "creates interface when it is absent" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))

      state = build_state()

      assert {:ok, %{action: :restart, changed: true}} =
               Converger.converge(state, instance, [], action: :restart, confirm: true)

      assert [{:up, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()
    end
  end

  describe "converge/4 :absent" do
    test "backs up config, downs interface and deletes config" do
      instance = build_instance("wg1", :wg)
      FakeConfigStore.set_config(:wg, "wg1", "old-config\n")

      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", "")

      state = build_state()

      assert {:ok, %{action: :absent, changed: true}} =
               Converger.converge(state, instance, [], action: :absent, confirm: true)

      assert FakeConfigStore.last_backup(:wg, "wg1") == "old-config\n"
      assert FakeConfigStore.read_config(:wg, "wg1") == {:error, :enoent}
      assert [{:down, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()
    end

    test "downs interface using existing config before deleting it" do
      instance = build_instance("wg1", :wg)
      FakeConfigStore.set_config(:wg, "wg1", "old-config\n")

      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", "")

      state = build_state()

      assert {:ok, %{action: :absent, changed: true}} =
               Converger.converge(state, instance, [], action: :absent, confirm: true)

      # down должен был вызваться по существующему пути; после converge конфиг удалён.
      assert [{:down, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()
      assert FakeConfigStore.read_config(:wg, "wg1") == {:error, :enoent}
      assert FakeConfigStore.last_backup(:wg, "wg1") == "old-config\n"
    end

    test "is no-op when config and interface are already absent" do
      instance = build_instance("wg1", :wg)

      state = build_state()

      assert {:ok, %{action: :absent, changed: false}} =
               Converger.converge(state, instance, [], action: :absent)

      assert FakeAdapter.calls() == []
    end

    test "requires confirmation when there is something to remove" do
      instance = build_instance("wg1", :wg)
      FakeConfigStore.set_config(:wg, "wg1", "old-config\n")
      FakeAdapter.set_interface_state("wg1", :up)

      assert {:error, "Destructive action absent requires confirmation"} =
               Converger.converge(build_state(), instance, [], action: :absent)
    end

    test "refuses to remove instance that has peers" do
      instance = build_instance("wg1", :wg)
      peer = build_peer("peer-1")

      assert {:error, "Instance has peers"} =
               Converger.converge(build_state(), instance, [peer], action: :absent, confirm: true)
    end
  end

  describe "write_stripped_temp/2" do
    test "creates temp file with 0600 and directory with 0700" do
      assert {:ok, path} = Converger.write_stripped_temp("private-key-data", "wg1")

      try do
        assert File.exists?(path)
        assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
        assert File.stat!(Path.dirname(path)).mode |> Bitwise.band(0o777) == 0o700
      after
        File.rm_rf(Path.dirname(path))
      end
    end
  end

  describe "converge/4 dry_run" do
    test "returns diff without applying changes" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      state = build_state()

      assert {:ok, %{action: :up, dry_run: true, diff: diff}} =
               Converger.converge(state, instance, [], action: :up, dry_run: true)

      assert Enum.any?(diff, &String.starts_with?(&1, "+"))
      assert FakeConfigStore.read_config(:wg, "wg1") == {:error, :enoent}
      assert FakeAdapter.calls() == []
    end
  end

  describe "FakeAdapter result injection" do
    test "set_up_result changes the result of up" do
      FakeAdapter.set_up_result(:wg, "wg1", {:error, "already exists"})

      assert {:error, "already exists"} =
               FakeAdapter.up(:wg, "wg1", "/fake/wg/wg1.conf")
    end

    test "set_down_result changes the result of down" do
      FakeAdapter.set_down_result(:wg, "wg1", {:error, "no such device"})

      assert {:error, "no such device"} =
               FakeAdapter.down(:wg, "wg1", "/fake/wg/wg1.conf")
    end
  end

  describe "FakeAdapter dump fixture" do
    test "down deletes the dump fixture" do
      instance = build_instance("wg1", :wg)
      FakeConfigStore.set_config(:wg, "wg1", "old-config\n")
      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))

      state = build_state()

      assert {:ok, %{action: :down, changed: true}} =
               Converger.converge(state, instance, [], action: :down, confirm: true)

      assert FakeAdapter.show_dump(:wg, "wg1") ==
               {:error, "No dump fixture for wg wg1"}
    end
  end

  describe "converge/4 with peers" do
    test "verifies that expected peers are present in dump" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      peer = build_peer("peer-1")

      dump =
        dump_for(instance) <>
          "peer-pub\t\t192.168.1.2:1234\t10.0.0.2/32\t1699013400\t0\t0\t0\n"

      FakeAdapter.set_dump(:wg, "wg1", dump)
      FakeAdapter.set_interface_state("wg1", :up)

      state = build_state()

      assert {:ok, %{action: :up, changed: true}} =
               Converger.converge(state, instance, [peer], action: :up)
    end
  end

  describe "lifecycle scenarios" do
    test "absent -> up -> down -> up -> restart -> absent" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      state = build_state()

      # :up on absent interface creates it
      FakeAdapter.set_interface_state("wg1", :unknown)
      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))

      assert {:ok, %{action: :up, changed: true}} =
               Converger.converge(state, instance, [], action: :up)

      # :up again is idempotent
      FakeAdapter.reset()
      FakeAdapter.set_interface_state("wg1", :up)

      assert {:ok, %{action: :up, changed: false}} =
               Converger.converge(state, instance, [], action: :up)

      assert FakeAdapter.calls() == []

      # :down stops it
      FakeAdapter.reset()
      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", "")

      assert {:ok, %{action: :down, changed: true}} =
               Converger.converge(state, instance, [], action: :down, confirm: true)

      assert [{:down, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()

      # :down again is no-op
      FakeAdapter.reset()
      FakeAdapter.set_interface_state("wg1", :down)

      assert {:ok, %{action: :down, changed: false}} =
               Converger.converge(state, instance, [], action: :down)

      assert FakeAdapter.calls() == []

      # :up on a down interface must first remove the existing interface,
      # because a real `wg-quick up` fails with "already exists" when the
      # interface is present (even if administratively down).
      FakeAdapter.reset()
      FakeAdapter.set_interface_state("wg1", :down)
      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))

      assert {:ok, %{action: :up, changed: true}} =
               Converger.converge(state, instance, [], action: :up)

      assert [
               {:down, :wg, "wg1", "/fake/wg/wg1.conf"},
               {:up, :wg, "wg1", "/fake/wg/wg1.conf"}
             ] = FakeAdapter.calls()

      # :restart downs and ups
      FakeAdapter.reset()
      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))

      assert {:ok, %{action: :restart, changed: true}} =
               Converger.converge(state, instance, [], action: :restart, confirm: true)

      assert [
               {:down, :wg, "wg1", "/fake/wg/wg1.conf"},
               {:up, :wg, "wg1", "/fake/wg/wg1.conf"}
             ] = FakeAdapter.calls()

      # :absent removes everything
      FakeAdapter.reset()
      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", "")

      assert {:ok, %{action: :absent, changed: true}} =
               Converger.converge(state, instance, [], action: :absent, confirm: true)

      assert [{:down, :wg, "wg1", "/fake/wg/wg1.conf"}] = FakeAdapter.calls()
      assert FakeConfigStore.read_config(:wg, "wg1") == {:error, :enoent}
    end

    test "existing interface -> :up syncconfs without creating it" do
      instance = build_instance("wg1", :wg)
      FakeKeyStore.set_private_key(:wg, "inst-wg1", "server-private-key")

      FakeAdapter.set_interface_state("wg1", :up)
      FakeAdapter.set_dump(:wg, "wg1", dump_for(instance))

      state = build_state()

      assert {:ok, %{action: :up, changed: true}} =
               Converger.converge(state, instance, [], action: :up)

      refute Enum.any?(FakeAdapter.calls(), fn call -> elem(call, 0) == :up end)
      assert Enum.any?(FakeAdapter.calls(), fn call -> elem(call, 0) == :syncconf end)
    end
  end

  defp build_instance(name, protocol) do
    %Instance{
      id: "inst-#{name}",
      node_id: "node-1",
      name: name,
      protocol: protocol,
      listen_port: 51820,
      subnet: "10.0.0.0/24",
      private_key: nil,
      public_key: "server-public-key-#{name}",
      address: "10.0.0.1/24",
      dns: nil,
      mtu: nil,
      awg_params: nil,
      target_state: :configured
    }
  end

  defp build_peer(id) do
    %Peer{
      id: id,
      instance_id: "inst-wg1",
      name: "laptop",
      private_key: "peer-priv",
      public_key: "peer-pub",
      preshared_key: nil,
      allowed_ips: "10.0.0.2/32",
      persistent_keepalive: nil,
      endpoint: nil,
      address: "10.0.0.2/32",
      dns: nil
    }
  end

  defp build_state do
    %{
      adapter: FakeAdapter,
      key_store: FakeKeyStore,
      config_store: FakeConfigStore
    }
  end

  defp dump_for(%Instance{} = instance) do
    "priv\t#{instance.public_key}\t#{instance.listen_port}\toff\n"
  end
end
