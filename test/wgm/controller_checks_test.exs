defmodule WGM.ControllerChecksTest do
  use ExUnit.Case

  alias WGM.{Agent.Status, Check, Controller}
  alias WGM.Controller.AgentAdapter.Fake, as: FakeAgentAdapter

  setup do
    FakeAgentAdapter.start()
    :ok
  end

  describe "passive checks" do
    test "scheduler stores passive check results from agent status" do
      controller = start_controller()
      register_node(controller, "node-1")

      agent_status = %Status{
        node_id: "node-1",
        timestamp: DateTime.utc_now(),
        instances: [
          %Status.InstanceStatus{
            instance_id: "inst-1",
            name: "wg1",
            protocol: :wg,
            interface_state: :up,
            present: true,
            device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
            peers: [
              %{
                public_key: "peer-1",
                preshared_key: "",
                endpoint: "192.168.1.2:1234",
                allowed_ips: "10.0.0.2/32",
                latest_handshake: 1_699_013_400,
                transfer_rx: 1024,
                transfer_tx: 2048,
                persistent_keepalive: 25
              }
            ],
            error: nil
          }
        ]
      }

      FakeAgentAdapter.set_status("node-1", {:ok, agent_status})

      GenServer.call(controller, :run_passive_checks)

      results = Controller.check_results(controller)
      assert length(results) == 3
      assert Enum.any?(results, &(&1.kind == :interface_state and &1.status == :ok))
      assert Enum.any?(results, &(&1.kind == :handshake and &1.status == :ok))
      assert Enum.any?(results, &(&1.kind == :transfer and &1.status == :ok))
    end

    test "offline agent stores reachability error and keeps last_contact" do
      controller = start_controller()
      register_node(controller, "node-1")

      contact = DateTime.from_iso8601("2026-10-23T10:00:00Z") |> elem(1)

      # Сначала агент был онлайн — last_contact сохранился.
      online_status = %Status{
        node_id: "node-1",
        timestamp: contact,
        instances: []
      }

      FakeAgentAdapter.set_status("node-1", {:ok, online_status})
      GenServer.call(controller, :run_passive_checks)

      # Теперь агент офлайн, но last_contact должен остаться.
      FakeAgentAdapter.set_status("node-1", {:error, "unreachable"})
      GenServer.call(controller, :run_passive_checks)

      [status] = Controller.status(controller)
      assert status.online == false
      assert status.last_contact == contact

      results = Controller.check_results(controller, node_id: "node-1", kind: :reachability)
      assert [%{kind: :reachability, status: :error}] = results
    end

    test "preserves last_success_at when a check transitions to error" do
      controller = start_controller()
      register_node(controller, "node-1")
      register_instance(controller, "node-1", "inst-1")

      t_ok = DateTime.from_iso8601("2026-10-23T10:00:00Z") |> elem(1)
      t_error = DateTime.from_iso8601("2026-10-23T10:01:00Z") |> elem(1)

      ok_status = %Status{
        node_id: "node-1",
        timestamp: t_ok,
        instances: [
          %Status.InstanceStatus{
            instance_id: "inst-1",
            name: "wg1",
            protocol: :wg,
            interface_state: :up,
            present: true,
            device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
            peers: [],
            error: nil
          }
        ]
      }

      error_status = %Status{
        node_id: "node-1",
        timestamp: t_error,
        instances: [
          %Status.InstanceStatus{
            instance_id: "inst-1",
            name: "wg1",
            protocol: :wg,
            interface_state: :down,
            present: true,
            device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
            peers: [],
            error: nil
          }
        ]
      }

      FakeAgentAdapter.set_status("node-1", {:ok, ok_status})
      GenServer.call(controller, :run_passive_checks)

      FakeAgentAdapter.set_status("node-1", {:ok, error_status})
      GenServer.call(controller, :run_passive_checks)

      [latest] =
        Controller.check_results(controller, instance_id: "inst-1", kind: :interface_state)

      assert latest.status == :error
      assert latest.checked_at == t_error
      assert latest.last_success_at == t_ok
    end
  end

  describe "active checks" do
    test "scheduler runs ping checks for every node" do
      controller = start_controller()
      register_node(controller, "node-1")
      register_node(controller, "node-2")

      now = DateTime.utc_now()

      FakeAgentAdapter.set_check_result(
        "node-1",
        :ping,
        nil,
        {:ok,
         %Check.Result{
           node_id: "node-1",
           instance_id: nil,
           peer_id: nil,
           kind: :ping,
           status: :ok,
           detail: "ping ok",
           checked_at: now,
           last_success_at: now
         }}
      )

      FakeAgentAdapter.set_check_result(
        "node-2",
        :ping,
        nil,
        {:ok,
         %Check.Result{
           node_id: "node-2",
           instance_id: nil,
           peer_id: nil,
           kind: :ping,
           status: :ok,
           detail: "ping ok",
           checked_at: now,
           last_success_at: now
         }}
      )

      GenServer.call(controller, :run_active_checks)

      results = Controller.check_results(controller, kind: :ping)
      assert length(results) == 2
    end

    test "run_active_check returns result and stores it" do
      controller = start_controller()
      register_node(controller, "node-1")

      now = DateTime.utc_now()

      FakeAgentAdapter.set_check_result(
        "node-1",
        :ping,
        "1.1.1.1",
        {:ok,
         %Check.Result{
           node_id: "node-1",
           instance_id: nil,
           peer_id: nil,
           kind: :ping,
           status: :ok,
           detail: "ping 1.1.1.1 ok",
           checked_at: now,
           last_success_at: now
         }}
      )

      assert {:ok, result} = Controller.run_active_check(controller, "node-1", :ping, "1.1.1.1")
      assert result.status == :ok
      assert result.detail == "ping 1.1.1.1 ok"

      [stored] = Controller.check_results(controller, node_id: "node-1", kind: :ping)
      assert stored.status == :ok
    end

    test "run_active_check returns error when node is missing" do
      controller = start_controller()

      assert {:error, "Node not found"} =
               Controller.run_active_check(controller, "missing", :ping)
    end

    test "scheduler runs end_to_end checks for assembled cascades" do
      controller = start_controller()
      register_node(controller, "entry-node", :entry)
      register_instance(controller, "entry-node", "entry-wg")
      register_instance(controller, "entry-node", "entry-transit", "awg-entry", "10.200.0.1/30")
      register_node(controller, "exit-node", :exit)
      register_instance(controller, "exit-node", "exit-awg")

      now = DateTime.utc_now()

      route = %{
        interface: "awg-entry",
        source_ip: "10.200.0.1",
        target: "8.8.8.8"
      }

      FakeAgentAdapter.set_check_result(
        "entry-node",
        :end_to_end,
        route,
        {:ok,
         %Check.Result{
           node_id: "entry-node",
           instance_id: nil,
           peer_id: nil,
           kind: :end_to_end,
           status: :ok,
           detail: "end-to-end ok",
           checked_at: now,
           last_success_at: now
         }}
      )

      # Store cascade with the transit instance already linked.
      :ok =
        WGM.Controller.Repo.insert_cascade(
          :sys.get_state(controller).conn,
          %WGM.Cascade{
            id: "cascade-1",
            entry_instance_id: "entry-wg",
            entry_transit_instance_id: "entry-transit",
            exit_instance_id: "exit-awg",
            target: "8.8.8.8"
          }
        )

      GenServer.call(controller, :run_active_checks)

      results = Controller.check_results(controller, kind: :end_to_end)
      assert length(results) == 1
      assert hd(results).status == :ok
      assert hd(results).detail == "end-to-end ok"
    end
  end

  describe "check_results/2" do
    test "filters by node_id and instance_id" do
      controller = start_controller()
      register_node(controller, "node-1")
      register_instance(controller, "node-1", "inst-1")

      agent_status = %Status{
        node_id: "node-1",
        timestamp: DateTime.utc_now(),
        instances: [
          %Status.InstanceStatus{
            instance_id: "inst-1",
            name: "wg1",
            protocol: :wg,
            interface_state: :up,
            present: true,
            device: %{public_key: "pub", listen_port: 51820, fwmark: "off"},
            peers: [],
            error: nil
          }
        ]
      }

      FakeAgentAdapter.set_status("node-1", {:ok, agent_status})
      GenServer.call(controller, :run_passive_checks)

      assert [%{instance_id: "inst-1"}] =
               Controller.check_results(controller, instance_id: "inst-1")

      assert Controller.check_results(controller, instance_id: "missing") == []
    end
  end

  defp start_controller do
    opts = [
      db_path: ":memory:",
      agent_adapter: FakeAgentAdapter,
      keygen_adapter: WGM.CLI.FakeAdapter,
      passive_interval_ms: 60_000,
      active_interval_ms: 60_000
    ]

    {:ok, controller} = Controller.start_link(opts)
    controller
  end

  defp register_node(controller, node_id, role \\ :entry) do
    attrs = %{
      id: node_id,
      name: node_id,
      address: "193.233.91.130",
      role: role
    }

    assert {:ok, ^node_id} = Controller.register_node(controller, "cmd-#{node_id}", attrs)
    :ok
  end

  defp register_instance(
         controller,
         node_id,
         instance_id,
         name \\ "wg1",
         address \\ "10.0.0.1/24"
       ) do
    FakeAgentAdapter.set_keypair(node_id, instance_id, :wg, "server-pub-#{instance_id}")

    attrs = %{
      id: instance_id,
      node_id: node_id,
      name: name,
      protocol: :wg,
      listen_port: 51820,
      subnet: "10.0.0.0/24",
      address: address
    }

    assert {:ok, ^instance_id} =
             Controller.create_instance(controller, "cmd-#{instance_id}", attrs)

    :ok
  end
end
