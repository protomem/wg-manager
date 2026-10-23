defmodule WGM.CheckTest do
  use ExUnit.Case

  alias WGM.{Agent.Status, Check}

  describe "from_agent_status/1" do
    test "derives ok checks for an up interface with active peer" do
      checked_at = DateTime.utc_now()

      peer = %{
        public_key: "peer-pub",
        preshared_key: "",
        endpoint: "192.168.1.2:1234",
        allowed_ips: "10.0.0.2/32",
        latest_handshake: 1_699_013_400,
        transfer_rx: 1024,
        transfer_tx: 2048,
        persistent_keepalive: 25
      }

      instance_status = %Status.InstanceStatus{
        instance_id: "inst-1",
        name: "wg1",
        protocol: :wg,
        interface_state: :up,
        present: true,
        device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
        peers: [peer],
        error: nil
      }

      status = %Status{
        node_id: "node-1",
        timestamp: checked_at,
        instances: [instance_status]
      }

      results = Check.from_agent_status(status)

      assert length(results) == 3

      assert %{status: :ok, kind: :interface_state} =
               find_result(results, :interface_state, "inst-1")

      assert %{status: :ok, kind: :handshake} =
               find_result(results, :handshake, "inst-1", "peer-pub")

      assert %{status: :ok, kind: :transfer} =
               find_result(results, :transfer, "inst-1", "peer-pub")
    end

    test "derives error interface_state when interface is down" do
      checked_at = DateTime.utc_now()

      instance_status = %Status.InstanceStatus{
        instance_id: "inst-1",
        name: "wg1",
        protocol: :wg,
        interface_state: :down,
        present: true,
        device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
        peers: [],
        error: nil
      }

      status = %Status{
        node_id: "node-1",
        timestamp: checked_at,
        instances: [instance_status]
      }

      results = Check.from_agent_status(status)

      assert %{status: :error, kind: :interface_state, detail: detail} =
               find_result(results, :interface_state, "inst-1")

      assert detail =~ "down"
    end

    test "derives unknown interface_state when interface state is unknown" do
      checked_at = DateTime.utc_now()

      instance_status = %Status.InstanceStatus{
        instance_id: "inst-1",
        name: "wg1",
        protocol: :wg,
        interface_state: :unknown,
        present: false,
        device: nil,
        peers: nil,
        error: "Interface wg1 not found"
      }

      status = %Status{
        node_id: "node-1",
        timestamp: checked_at,
        instances: [instance_status]
      }

      results = Check.from_agent_status(status)

      assert %{status: :unknown, kind: :interface_state} =
               find_result(results, :interface_state, "inst-1")
    end

    test "derives error handshake and transfer for a peer without traffic" do
      checked_at = DateTime.utc_now()

      peer = %{
        public_key: "peer-pub",
        preshared_key: "",
        endpoint: "192.168.1.2:1234",
        allowed_ips: "10.0.0.2/32",
        latest_handshake: 0,
        transfer_rx: 0,
        transfer_tx: 0,
        persistent_keepalive: 25
      }

      instance_status = %Status.InstanceStatus{
        instance_id: "inst-1",
        name: "wg1",
        protocol: :wg,
        interface_state: :up,
        present: true,
        device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
        peers: [peer],
        error: nil
      }

      status = %Status{
        node_id: "node-1",
        timestamp: checked_at,
        instances: [instance_status]
      }

      results = Check.from_agent_status(status)

      assert %{status: :error, kind: :handshake} =
               find_result(results, :handshake, "inst-1", "peer-pub")

      assert %{status: :error, kind: :transfer} =
               find_result(results, :transfer, "inst-1", "peer-pub")
    end

    test "derives per-peer results" do
      checked_at = DateTime.utc_now()

      peers = [
        %{
          public_key: "peer-1",
          preshared_key: "",
          endpoint: "192.168.1.2:1234",
          allowed_ips: "10.0.0.2/32",
          latest_handshake: 1_699_013_400,
          transfer_rx: 100,
          transfer_tx: 200,
          persistent_keepalive: 25
        },
        %{
          public_key: "peer-2",
          preshared_key: "",
          endpoint: "192.168.1.3:1234",
          allowed_ips: "10.0.0.3/32",
          latest_handshake: 0,
          transfer_rx: 0,
          transfer_tx: 0,
          persistent_keepalive: 25
        }
      ]

      instance_status = %Status.InstanceStatus{
        instance_id: "inst-1",
        name: "wg1",
        protocol: :wg,
        interface_state: :up,
        present: true,
        device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
        peers: peers,
        error: nil
      }

      status = %Status{
        node_id: "node-1",
        timestamp: checked_at,
        instances: [instance_status]
      }

      results = Check.from_agent_status(status)

      handshake_results = Enum.filter(results, &(&1.kind == :handshake))
      assert length(handshake_results) == 2

      assert Enum.any?(handshake_results, &(&1.peer_id == "peer-1" and &1.status == :ok))
      assert Enum.any?(handshake_results, &(&1.peer_id == "peer-2" and &1.status == :error))
    end
  end

  defp find_result(results, kind, instance_id, peer_id \\ nil) do
    Enum.find(
      results,
      &(&1.kind == kind and &1.instance_id == instance_id and &1.peer_id == peer_id)
    )
  end
end
