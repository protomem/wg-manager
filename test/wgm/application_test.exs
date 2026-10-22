defmodule WGM.ApplicationTest do
  use ExUnit.Case

  alias WGM.{Agent, Controller}

  setup do
    on_exit(fn ->
      Enum.each(
        [
          "WGM_MODE",
          "WGM_NODE_ID",
          "WGM_NODE_NAME",
          "WGM_NODE_ADDRESS",
          "WGM_NODE_ROLE",
          "WGM_AGENT_READ_ONLY",
          "WGM_DB_PATH"
        ],
        &System.delete_env/1
      )
    end)
  end

  describe "mode/0" do
    test "returns :agent when WGM_MODE=agent" do
      System.put_env("WGM_MODE", "agent")
      assert WGM.Application.mode() == :agent
    end

    test "returns :controller when WGM_MODE=controller" do
      System.put_env("WGM_MODE", "controller")
      assert WGM.Application.mode() == :controller
    end

    test "falls back to application env when WGM_MODE is unset" do
      System.delete_env("WGM_MODE")
      Application.put_env(:wgm, :mode, :none)
      assert WGM.Application.mode() == :none
    end

    test "environment variable overrides application env" do
      System.put_env("WGM_MODE", "controller")
      Application.put_env(:wgm, :mode, :agent)
      assert WGM.Application.mode() == :controller
    end
  end

  describe "children/0 in agent mode" do
    test "returns a single Agent child spec with node metadata" do
      System.put_env("WGM_MODE", "agent")
      System.put_env("WGM_NODE_ID", "node-1")
      System.put_env("WGM_NODE_NAME", "entry")
      System.put_env("WGM_NODE_ADDRESS", "193.233.91.130")
      System.put_env("WGM_NODE_ROLE", "entry")

      assert [{Agent, opts}] = WGM.Application.children()
      assert opts[:name] == :wgm_agent
      assert opts[:node].id == "node-1"
      assert opts[:node].name == "entry"
      assert opts[:node].address == "193.233.91.130"
      assert opts[:node].role == :entry
      assert opts[:instances] == []
      assert opts[:read_only] == true
    end

    test "allows disabling read-only mode via WGM_AGENT_READ_ONLY=false" do
      System.put_env("WGM_MODE", "agent")
      System.put_env("WGM_NODE_ID", "node-1")
      System.put_env("WGM_NODE_NAME", "entry")
      System.put_env("WGM_NODE_ADDRESS", "193.233.91.130")
      System.put_env("WGM_NODE_ROLE", "entry")
      System.put_env("WGM_AGENT_READ_ONLY", "false")

      assert [{Agent, opts}] = WGM.Application.children()
      assert opts[:read_only] == false
    end

    test "defaults unknown role to :standalone" do
      System.put_env("WGM_MODE", "agent")
      System.put_env("WGM_NODE_ID", "node-2")
      System.put_env("WGM_NODE_NAME", "lonely")
      System.put_env("WGM_NODE_ADDRESS", "5.129.219.31")
      System.put_env("WGM_NODE_ROLE", "unknown")

      assert [{Agent, opts}] = WGM.Application.children()
      assert opts[:node].role == :standalone
    end

    test "raises when required node variables are missing" do
      System.put_env("WGM_MODE", "agent")
      System.delete_env("WGM_NODE_ID")

      assert_raise RuntimeError, ~r/Missing required environment variable/, fn ->
        WGM.Application.children()
      end
    end
  end

  describe "children/0 in controller mode" do
    test "returns a single Controller child spec with the configured db path" do
      System.put_env("WGM_MODE", "controller")
      System.put_env("WGM_DB_PATH", "/opt/wgm/db/controller.db")

      assert [{Controller, opts}] = WGM.Application.children()
      assert opts[:name] == :wgm_controller
      assert opts[:db_path] == "/opt/wgm/db/controller.db"
    end

    test "uses the default db path when WGM_DB_PATH is unset" do
      System.put_env("WGM_MODE", "controller")
      System.delete_env("WGM_DB_PATH")

      assert [{Controller, opts}] = WGM.Application.children()
      assert opts[:db_path] == "/var/lib/wgm/controller.db"
    end
  end

  describe "children/0 in default mode" do
    test "returns an empty list" do
      System.delete_env("WGM_MODE")
      Application.put_env(:wgm, :mode, :none)

      assert WGM.Application.children() == []
    end
  end
end
