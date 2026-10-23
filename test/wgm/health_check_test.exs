defmodule WGM.HealthCheckTest do
  use ExUnit.Case

  alias WGM.{Agent.Checker, HealthCheck}

  setup do
    HealthCheck.FakeAdapter.start()
    :ok
  end

  describe "FakeAdapter" do
    test "returns configured ping result" do
      HealthCheck.FakeAdapter.set_ping_result(
        "1.1.1.1",
        {:ok, "1 packets transmitted, 1 received"}
      )

      assert {:ok, "1 packets transmitted, 1 received"} = HealthCheck.FakeAdapter.ping("1.1.1.1")
    end

    test "returns error when ping result is not configured" do
      assert {:error, "No ping fixture for 8.8.8.8"} = HealthCheck.FakeAdapter.ping("8.8.8.8")
    end

    test "returns configured end_to_end result" do
      HealthCheck.FakeAdapter.set_end_to_end_result(["10.0.0.1", "10.0.0.2"], {:ok, "reachable"})

      assert {:ok, "reachable"} =
               HealthCheck.FakeAdapter.end_to_end(["10.0.0.1", "10.0.0.2"])
    end
  end

  describe "Checker.run_active/4" do
    test "returns ok ping result" do
      HealthCheck.FakeAdapter.set_ping_result("1.1.1.1", {:ok, "ping ok"})

      result = Checker.run_active("node-1", :ping, "1.1.1.1", HealthCheck.FakeAdapter)

      assert result.node_id == "node-1"
      assert result.kind == :ping
      assert result.status == :ok
      assert result.detail == "ping ok"
      assert result.last_success_at == result.checked_at
    end

    test "returns error ping result and no last_success_at" do
      HealthCheck.FakeAdapter.set_ping_result("1.1.1.1", {:error, "timeout"})

      result = Checker.run_active("node-1", :ping, "1.1.1.1", HealthCheck.FakeAdapter)

      assert result.status == :error
      assert result.detail == "timeout"
      assert result.last_success_at == nil
    end

    test "uses default ping target when target is nil" do
      HealthCheck.FakeAdapter.set_ping_result("1.1.1.1", {:ok, "ping ok"})

      result = Checker.run_active("node-1", :ping, nil, HealthCheck.FakeAdapter)

      assert result.status == :ok
      assert result.detail == "ping ok"
    end

    test "returns end_to_end result" do
      HealthCheck.FakeAdapter.set_end_to_end_result(["10.0.0.1", "10.0.0.2"], {:ok, "reachable"})

      result =
        Checker.run_active(
          "node-1",
          :end_to_end,
          ["10.0.0.1", "10.0.0.2"],
          HealthCheck.FakeAdapter
        )

      assert result.kind == :end_to_end
      assert result.status == :ok
      assert result.detail == "reachable"
    end

    test "returns end_to_end result for map route" do
      route = %{interface: "awg-entry", source_ip: "10.200.0.1", target: "1.1.1.1"}

      HealthCheck.FakeAdapter.set_end_to_end_result(
        route,
        {:ok, "end-to-end through awg-entry to 1.1.1.1 ok"}
      )

      result = Checker.run_active("node-1", :end_to_end, route, HealthCheck.FakeAdapter)

      assert result.kind == :end_to_end
      assert result.status == :ok
      assert result.detail == "end-to-end through awg-entry to 1.1.1.1 ok"
    end

    test "distinguishes error states for map route" do
      route_down = %{interface: "awg-entry", source_ip: "10.200.0.1", target: "1.1.1.1"}

      HealthCheck.FakeAdapter.set_end_to_end_result(
        route_down,
        {:error, "interface awg-entry is not up"}
      )

      result = Checker.run_active("node-1", :end_to_end, route_down, HealthCheck.FakeAdapter)

      assert result.status == :error
      assert result.detail == "interface awg-entry is not up"
    end
  end
end
