defmodule WGM.ClientTest do
  use ExUnit.Case

  alias WGM.{Client, Controller, Instance, Peer}
  alias WGM.Controller.AgentAdapter.Fake

  @moduletag :tmp_dir

  setup do
    Fake.start()
    :ok
  end

  describe "help/0" do
    test "returns usage information" do
      help = Client.help()

      assert help =~ "WGM.Client"
      assert help =~ "connect"
      assert help =~ "status"
      assert help =~ "list_instances"
      assert help =~ "list_peers"
      assert help =~ "create_peer"
      assert help =~ "delete_peer"
      assert help =~ "store_client_config"
      assert help =~ "get_client_config"
      assert help =~ "write_client_config"
      assert help =~ "show_client_config_qr"
    end
  end

  describe "connect/2" do
    test "returns error when Erlang distribution is not enabled" do
      assert :erlang.node() == :nonode@nohost

      assert {:error, "Erlang distribution is not enabled"} =
               Client.connect("wgm_controller@127.0.0.1", "cookie")
    end
  end

  describe "status/1" do
    test "returns aggregated status from controller" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")

      agent_status = %WGM.Agent.Status{
        node_id: "node-1",
        timestamp: DateTime.utc_now(),
        instances: []
      }

      Fake.set_status("node-1", {:ok, agent_status})

      assert {:ok, [status]} = Client.status(node())
      assert status.node_id == "node-1"
      assert status.node_name == "node-1"
      assert status.online
      assert status.agent_status.node_id == "node-1"
    end

    test "returns offline status when agent is unreachable" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")

      assert {:ok, [status]} = Client.status(node())
      assert status.node_id == "node-1"
      refute status.online
      assert status.agent_status == nil
    end

    test "returns error when controller is not running" do
      assert {:error, _reason} = Client.status(node())
    end
  end

  describe "desired state queries" do
    test "list_nodes/1, list_instances/1, list_peers/1 return controller data" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")
      :ok = register_instance(controller, "node-1", "inst-1")
      :ok = register_peer(controller, "inst-1", "peer-1")

      assert {:ok, [%WGM.Node{id: "node-1"}]} = Client.list_nodes(node())
      assert {:ok, [%Instance{id: "inst-1"}]} = Client.list_instances(node())
      assert {:ok, [%Peer{id: "peer-1"}]} = Client.list_peers(node())
    end

    test "get_peer/2 returns peer by id" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      assert {:ok, %Peer{id: "peer-1", name: "laptop"}} = Client.get_peer(node(), "peer-1")
      assert {:ok, nil} = Client.get_peer(node(), "missing")
    end
  end

  describe "peer operations" do
    test "create_peer/3 creates a peer through the controller" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")
      :ok = register_instance(controller, "node-1", "inst-1")

      assert {:ok, "peer-1"} =
               Client.create_peer(node(), "cmd-peer", peer_attrs("inst-1", "peer-1"))

      assert {:ok, %Peer{id: "peer-1", name: "laptop"}} = Client.get_peer(node(), "peer-1")
    end

    test "create_peer/3 returns error when instance does not exist" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")

      assert {:error, "Instance not found"} =
               Client.create_peer(node(), "cmd-peer", peer_attrs("missing", "peer-1"))
    end

    test "delete_peer/4 removes a peer when confirmed" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      assert {:ok, "peer-1"} = Client.delete_peer(node(), "cmd-del", "peer-1", confirm: true)
      assert {:ok, nil} = Client.get_peer(node(), "peer-1")
    end

    test "delete_peer/4 refuses removal without confirmation" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      assert {:error, "Destructive action delete_peer requires confirmation"} =
               Client.delete_peer(node(), "cmd-del", "peer-1")

      assert {:ok, %Peer{id: "peer-1"}} = Client.get_peer(node(), "peer-1")
    end

    test "delete_peer/4 returns error when peer does not exist" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")
      :ok = register_instance(controller, "node-1", "inst-1")

      assert {:error, "Peer not found"} =
               Client.delete_peer(node(), "cmd-del", "missing", confirm: true)
    end
  end

  describe "client config operations" do
    test "store_client_config/4 generates and stores a client config" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      assert {:ok, config} =
               Client.store_client_config(node(), "cmd-config", "peer-1", "193.233.91.130:51820")

      assert config =~ "[Interface]"
      assert config =~ "[Peer]"
      assert config =~ "Endpoint = 193.233.91.130:51820"

      assert {:ok, ^config} = Client.get_client_config(node(), "peer-1")
    end

    test "store_client_config/4 returns error when peer does not exist" do
      controller = start_controller()
      :ok = register_node(controller, "node-1")
      :ok = register_instance(controller, "node-1", "inst-1")

      assert {:error, "Peer or instance not found"} =
               Client.store_client_config(node(), "cmd-config", "missing", "193.233.91.130:51820")
    end

    test "write_client_config/3 writes the stored config to a file" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      {:ok, config} =
        Client.store_client_config(node(), "cmd-config", "peer-1", "193.233.91.130:51820")

      path = Path.join(System.tmp_dir!(), "wgm-peer-1.conf")
      on_exit(fn -> File.rm(path) end)

      assert :ok = Client.write_client_config(node(), "peer-1", path)
      assert File.read!(path) == config
    end

    test "write_client_config/3 creates file with 0o600 permissions" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      Client.store_client_config(node(), "cmd-config", "peer-1", "193.233.91.130:51820")

      path = Path.join(System.tmp_dir!(), "wgm-peer-secret.conf")
      on_exit(fn -> File.rm(path) end)

      assert :ok = Client.write_client_config(node(), "peer-1", path)
      assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
    end

    test "write_client_config/3 returns error as string on filesystem failure" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      Client.store_client_config(node(), "cmd-config", "peer-1", "193.233.91.130:51820")

      path = "/nonexistent/wgm-peer-1.conf"

      assert {:error, reason} = Client.write_client_config(node(), "peer-1", path)
      assert is_binary(reason)
      assert reason != ""
    end

    test "write_client_config/3 returns error when no config is stored" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      path = Path.join(System.tmp_dir!(), "wgm-peer-missing.conf")

      assert {:error, "Client config not found"} =
               Client.write_client_config(node(), "peer-1", path)
    end

    test "show_client_config_qr/2 prints a QR code for the stored config" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      Client.store_client_config(node(), "cmd-config", "peer-1", "193.233.91.130:51820")

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert :ok = Client.show_client_config_qr(node(), "peer-1")
        end)

      assert output != ""
      assert String.contains?(output, "\e[")
    end

    test "show_client_config_qr/2 returns error when no config is stored" do
      controller = start_controller()
      :ok = register_peer_with_instance(controller, "inst-1", "peer-1")

      assert {:error, "Client config not found"} =
               Client.show_client_config_qr(node(), "peer-1")
    end
  end

  describe "write_file_private/3" do
    test "writes content and sets final file permissions to 0o600", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "wgm-secret.conf")

      assert :ok = Client.write_file_private(path, "secret-config")
      assert File.read!(path) == "secret-config"
      assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
    end

    test "overwrites an existing target file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "wgm-secret.conf")
      File.write!(path, "old-config")

      assert :ok = Client.write_file_private(path, "new-config")
      assert File.read!(path) == "new-config"
      assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
    end

    test "leaves no temp files after a successful write", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "wgm-secret.conf")

      assert :ok = Client.write_file_private(path, "secret-config")
      assert Path.wildcard(Path.join(tmp_dir, ".wgm-secret.conf.*.tmp")) == []
    end

    test "removes the temp file when rename fails", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "wgm-secret.conf")

      assert {:error, _reason} =
               Client.write_file_private(path, "secret-config", fn _src, _dst ->
                 {:error, :eacces}
               end)

      assert Path.wildcard(Path.join(tmp_dir, ".wgm-secret.conf.*.tmp")) == []
    end

    test "temp file is created with 0o600 permissions even if rename crashes", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "wgm-secret.conf")
      test_pid = self()

      assert_raise RuntimeError, "boom", fn ->
        Client.write_file_private(path, "secret-config", fn src, _dst ->
          send(test_pid, {:tmp_path, src})
          raise "boom"
        end)
      end

      assert_receive {:tmp_path, tmp_path}, 1_000
      assert File.exists?(tmp_path)
      assert File.stat!(tmp_path).mode |> Bitwise.band(0o777) == 0o600

      File.rm!(tmp_path)
    end
  end

  defp start_controller do
    {:ok, controller} =
      Controller.start_link(
        db_path: ":memory:",
        name: :wgm_controller,
        agent_adapter: Fake,
        keygen_adapter: WGM.CLI.FakeAdapter
      )

    on_exit(fn ->
      if pid = Process.whereis(:wgm_controller) do
        Process.exit(pid, :shutdown)
      end
    end)

    controller
  end

  defp register_node(controller, id) do
    attrs = %{id: id, name: id, address: "193.233.91.130", role: :entry}
    assert {:ok, ^id} = Controller.register_node(controller, "cmd-#{id}", attrs)
    :ok
  end

  defp register_instance(controller, node_id, id) do
    Fake.set_keypair(node_id, id, :wg, "server-pub-#{id}")

    attrs = %{
      id: id,
      node_id: node_id,
      name: "wg1",
      protocol: :wg,
      listen_port: 51820,
      subnet: "10.0.0.0/24",
      address: "10.0.0.1/24"
    }

    assert {:ok, ^id} = Controller.create_instance(controller, "cmd-#{id}", attrs)
    :ok
  end

  defp register_peer_with_instance(controller, instance_id, peer_id) do
    :ok = register_node(controller, "node-1")
    :ok = register_instance(controller, "node-1", instance_id)
    :ok = register_peer(controller, instance_id, peer_id)
  end

  defp register_peer(controller, instance_id, id) do
    assert {:ok, ^id} =
             Controller.create_peer(controller, "cmd-#{id}", peer_attrs(instance_id, id))

    :ok
  end

  defp peer_attrs(instance_id, id) do
    %{
      id: id,
      instance_id: instance_id,
      name: "laptop",
      allowed_ips: "10.0.0.2/32",
      address: "10.0.0.2/32"
    }
  end
end
