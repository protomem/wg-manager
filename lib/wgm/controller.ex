defmodule WGM.Controller do
  @moduledoc """
  Контроллер системы WG/AWG-VPN.

  Хранит желаемое состояние (узлы, инстансы, пиры, клиентские конфиги)
  в exqlite, ведёт журнал команд с дедупликацией по command_id и аудит
  без секретов. Подключается к агентам узлов через настраиваемый адаптер
  (по умолчанию — Erlang distribution).
  """

  use GenServer

  alias WGM.{ConfigGenerator, Instance, Keygen, Node, Peer}
  alias WGM.AWGParamsValidator
  alias WGM.Controller.{AgentAdapter, Repo, Status}

  defstruct [:conn, :agent_adapter, :keygen_adapter]

  @type command_id :: String.t()
  @type command_result :: {:ok, String.t()} | {:error, String.t()}

  @default_db_path "wgm-controller.db"

  @doc """
  Запускает контроллер.

  Опции:
    - `:db_path` — путь к файлу SQLite (по умолчанию `#{@default_db_path}`);
    - `:agent_adapter` — модуль адаптера агента (по умолчанию
      `WGM.Controller.AgentAdapter.Distribution`);
    - `:keygen_adapter` — CLI-адаптер для генерации ключей (по умолчанию
      `WGM.CLI.SystemAdapter`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec list_nodes(GenServer.server()) :: [Node.t()]
  def list_nodes(controller) do
    GenServer.call(controller, :list_nodes)
  end

  @spec get_node(GenServer.server(), String.t()) :: Node.t() | nil
  def get_node(controller, id) do
    GenServer.call(controller, {:get_node, id})
  end

  @spec register_node(GenServer.server(), command_id(), map()) :: command_result()
  def register_node(controller, command_id, attrs) do
    GenServer.call(controller, {:register_node, command_id, attrs})
  end

  @spec delete_node(GenServer.server(), command_id(), String.t()) :: command_result()
  def delete_node(controller, command_id, node_id) do
    GenServer.call(controller, {:delete_node, command_id, node_id})
  end

  @spec list_instances(GenServer.server(), String.t() | nil) :: [Instance.t()]
  def list_instances(controller, node_id \\ nil) do
    GenServer.call(controller, {:list_instances, node_id})
  end

  @spec get_instance(GenServer.server(), String.t()) :: Instance.t() | nil
  def get_instance(controller, id) do
    GenServer.call(controller, {:get_instance, id})
  end

  @spec create_instance(GenServer.server(), command_id(), map()) :: command_result()
  def create_instance(controller, command_id, attrs) do
    GenServer.call(controller, {:create_instance, command_id, attrs})
  end

  @spec delete_instance(GenServer.server(), command_id(), String.t()) :: command_result()
  def delete_instance(controller, command_id, instance_id) do
    GenServer.call(controller, {:delete_instance, command_id, instance_id})
  end

  @spec converge_instance(GenServer.server(), command_id(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def converge_instance(controller, command_id, instance_id, opts \\ []) do
    GenServer.call(controller, {:converge_instance, command_id, instance_id, opts})
  end

  @spec start_instance(GenServer.server(), command_id(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def start_instance(controller, command_id, instance_id) do
    converge_instance(controller, command_id, instance_id, action: :up)
  end

  @spec stop_instance(GenServer.server(), command_id(), String.t(), boolean()) ::
          {:ok, map()} | {:error, String.t()}
  def stop_instance(controller, command_id, instance_id, confirm) do
    converge_instance(controller, command_id, instance_id, action: :down, confirm: confirm)
  end

  @spec restart_instance(GenServer.server(), command_id(), String.t(), boolean()) ::
          {:ok, map()} | {:error, String.t()}
  def restart_instance(controller, command_id, instance_id, confirm) do
    converge_instance(controller, command_id, instance_id, action: :restart, confirm: confirm)
  end

  @spec delete_instance(GenServer.server(), command_id(), String.t(), boolean()) ::
          {:ok, map()} | {:error, String.t()}
  def delete_instance(controller, command_id, instance_id, confirm) do
    converge_instance(controller, command_id, instance_id, action: :absent, confirm: confirm)
  end

  @spec list_peers(GenServer.server(), String.t() | nil) :: [Peer.t()]
  def list_peers(controller, instance_id \\ nil) do
    GenServer.call(controller, {:list_peers, instance_id})
  end

  @spec get_peer(GenServer.server(), String.t()) :: Peer.t() | nil
  def get_peer(controller, id) do
    GenServer.call(controller, {:get_peer, id})
  end

  @spec create_peer(GenServer.server(), command_id(), map()) :: command_result()
  def create_peer(controller, command_id, attrs) do
    GenServer.call(controller, {:create_peer, command_id, attrs})
  end

  @spec delete_peer(GenServer.server(), command_id(), String.t()) :: command_result()
  def delete_peer(controller, command_id, peer_id) do
    GenServer.call(controller, {:delete_peer, command_id, peer_id})
  end

  @spec store_client_config(GenServer.server(), command_id(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_client_config(controller, command_id, peer_id, endpoint) do
    GenServer.call(controller, {:store_client_config, command_id, peer_id, endpoint})
  end

  @spec get_client_config(GenServer.server(), String.t()) :: String.t() | nil
  def get_client_config(controller, peer_id) do
    GenServer.call(controller, {:get_client_config, peer_id})
  end

  @spec status(GenServer.server()) :: [Status.t()]
  def status(controller) do
    GenServer.call(controller, :status)
  end

  @spec audit(GenServer.server()) :: [map()]
  def audit(controller) do
    GenServer.call(controller, :audit)
  end

  @spec command_log(GenServer.server()) :: [map()]
  def command_log(controller) do
    GenServer.call(controller, :command_log)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    db_path = opts[:db_path] || @default_db_path

    with {:ok, conn} <- Repo.open(db_path),
         :ok <- Repo.migrate(conn) do
      state = %__MODULE__{
        conn: conn,
        agent_adapter: opts[:agent_adapter] || AgentAdapter.Distribution,
        keygen_adapter: opts[:keygen_adapter] || WGM.CLI.SystemAdapter
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:list_nodes, _from, state) do
    {:reply, Repo.list_nodes(state.conn), state}
  end

  def handle_call({:get_node, id}, _from, state) do
    {:reply, Repo.get_node(state.conn, id), state}
  end

  def handle_call({:register_node, command_id, attrs}, _from, state) do
    node = %Node{
      id: attrs[:id],
      name: attrs[:name],
      address: attrs[:address],
      role: attrs[:role],
      description: attrs[:description]
    }

    summary = "registered node #{node.id} (#{node.name}, #{node.role})"

    result =
      execute_command(state, command_id, "register_node", node.id, summary, fn ->
        case Repo.insert_node(state.conn, node) do
          :ok -> {:ok, node.id}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:delete_node, command_id, node_id}, _from, state) do
    summary = "deleted node #{node_id}"

    result =
      execute_command(state, command_id, "delete_node", node_id, summary, fn ->
        with %Node{} <- Repo.get_node(state.conn, node_id),
             [] <- Repo.list_instances(state.conn, node_id),
             :ok <- Repo.delete_node(state.conn, node_id) do
          {:ok, node_id}
        else
          nil -> {:error, "Node not found"}
          [_ | _] -> {:error, "Node has instances"}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:list_instances, node_id}, _from, state) do
    instances =
      if node_id do
        Repo.list_instances(state.conn, node_id)
      else
        Repo.list_instances(state.conn)
      end

    {:reply, instances, state}
  end

  def handle_call({:get_instance, id}, _from, state) do
    {:reply, Repo.get_instance(state.conn, id), state}
  end

  def handle_call({:create_instance, command_id, attrs}, _from, state) do
    summary =
      "created instance #{attrs[:id]} on node #{attrs[:node_id]} protocol #{attrs[:protocol]}"

    result =
      execute_command(state, command_id, "create_instance", attrs[:id], summary, fn ->
        with {:ok, node} <- fetch_node(state.conn, attrs[:node_id]),
             {:ok, instance, action} <- build_instance(state, node, attrs),
             :ok <- maybe_insert_instance(state.conn, instance, action) do
          {:ok, attrs[:id]}
        else
          {:error, reason} -> {:error, reason}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:delete_instance, command_id, instance_id}, _from, state) do
    summary = "deleted instance #{instance_id}"

    result =
      execute_command(state, command_id, "delete_instance", instance_id, summary, fn ->
        with %Instance{} <- Repo.get_instance(state.conn, instance_id),
             [] <- Repo.list_peers(state.conn, instance_id),
             :ok <- Repo.delete_instance(state.conn, instance_id) do
          {:ok, instance_id}
        else
          nil -> {:error, "Instance not found"}
          [_ | _] -> {:error, "Instance has peers"}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:converge_instance, command_id, instance_id, opts}, _from, state) do
    action = opts[:action] || :up
    confirm = Keyword.get(opts, :confirm, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    summary = "converge instance #{instance_id} action #{action}"

    result =
      execute_command(
        state,
        command_id,
        "converge_instance",
        instance_id,
        summary,
        fn ->
          with {:ok, instance, node} <- fetch_instance_and_node(state.conn, instance_id),
               peers = Repo.list_peers(state.conn, instance_id),
               :ok <- validate_converge_preconditions(action, peers),
               {:ok, result} <-
                 state.agent_adapter.apply_instance(node, instance, peers,
                   action: action,
                   confirm: confirm,
                   dry_run: dry_run
                 ),
               :ok <- persist_target_state(state.conn, instance, action, dry_run) do
            {:ok, result}
          else
            nil -> {:error, "Instance not found"}
            {:error, reason} -> {:error, reason}
          end
        end,
        &encode_converge_result/1,
        &replay_converge_result/1
      )

    {:reply, result, state}
  end

  def handle_call({:list_peers, instance_id}, _from, state) do
    peers =
      if instance_id do
        Repo.list_peers(state.conn, instance_id)
      else
        Repo.list_peers(state.conn)
      end

    {:reply, peers, state}
  end

  def handle_call({:get_peer, id}, _from, state) do
    {:reply, Repo.get_peer(state.conn, id), state}
  end

  def handle_call({:create_peer, command_id, attrs}, _from, state) do
    instance_id = attrs[:instance_id]
    summary = "created peer #{attrs[:id]} on instance #{instance_id}"

    result =
      execute_command(state, command_id, "create_peer", attrs[:id], summary, fn ->
        with %Instance{} = instance <- Repo.get_instance(state.conn, instance_id),
             {:ok, keys} <- Keygen.generate_keypair(instance.protocol, state.keygen_adapter),
             {:ok, psk} <- Keygen.generate_psk(state.keygen_adapter),
             peer = build_peer(attrs, keys, psk),
             :ok <- Repo.insert_peer(state.conn, peer) do
          {:ok, peer.id}
        else
          nil -> {:error, "Instance not found"}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:delete_peer, command_id, peer_id}, _from, state) do
    summary = "deleted peer #{peer_id}"

    result =
      execute_command(state, command_id, "delete_peer", peer_id, summary, fn ->
        with %Peer{} <- Repo.get_peer(state.conn, peer_id),
             :ok <- Repo.delete_peer(state.conn, peer_id) do
          {:ok, peer_id}
        else
          nil -> {:error, "Peer not found"}
          {:error, reason} -> {:error, reason}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:store_client_config, command_id, peer_id, endpoint}, _from, state) do
    summary = "stored client config for peer #{peer_id}"

    log_result = fn _config -> "stored client config for peer #{peer_id}" end

    replay = fn
      %{status: "ok"} ->
        case Repo.get_client_config(state.conn, peer_id) do
          nil -> {:error, "Client config not found"}
          config -> {:ok, config}
        end

      %{status: "error", result: reason} ->
        {:error, reason}
    end

    result =
      execute_command(
        state,
        command_id,
        "store_client_config",
        peer_id,
        summary,
        fn ->
          with %Peer{} = peer <- Repo.get_peer(state.conn, peer_id),
               %Instance{} = instance <- Repo.get_instance(state.conn, peer.instance_id),
               {:ok, config} <- ConfigGenerator.generate_client_config(instance, peer, endpoint),
               :ok <- Repo.upsert_client_config(state.conn, peer_id, config) do
            {:ok, config}
          else
            nil -> {:error, "Peer or instance not found"}
            {:error, reason} -> {:error, reason}
          end
        end,
        log_result,
        replay
      )

    {:reply, result, state}
  end

  def handle_call({:get_client_config, peer_id}, _from, state) do
    {:reply, Repo.get_client_config(state.conn, peer_id), state}
  end

  def handle_call(:status, _from, state) do
    statuses =
      state.conn
      |> Repo.list_nodes()
      |> Enum.map(&node_status(&1, state.agent_adapter))

    {:reply, statuses, state}
  end

  def handle_call(:audit, _from, state) do
    {:reply, Repo.list_audit(state.conn), state}
  end

  def handle_call(:command_log, _from, state) do
    {:reply, Repo.list_commands(state.conn), state}
  end

  # Private helpers

  defp execute_command(
         state,
         command_id,
         type,
         object_id,
         summary,
         operation,
         log_result \\ &to_text/1,
         replay \\ nil
       ) do
    case Repo.get_command(state.conn, command_id) do
      %{} = record when is_function(replay, 1) ->
        replay.(record)

      %{status: "ok", result: result} ->
        {:ok, result}

      %{status: "error", result: result} ->
        {:error, result}

      nil ->
        case operation.() do
          {:ok, result} ->
            :ok =
              Repo.log_command(
                state.conn,
                command_id,
                type,
                object_id,
                "ok",
                log_result.(result)
              )

            :ok =
              Repo.append_audit(
                state.conn,
                command_id,
                type,
                object_id,
                "controller",
                "ok",
                summary
              )

            {:ok, result}

          {:error, reason} ->
            :ok =
              Repo.log_command(state.conn, command_id, type, object_id, "error", to_text(reason))

            :ok =
              Repo.append_audit(
                state.conn,
                command_id,
                type,
                object_id,
                "controller",
                "error",
                summary
              )

            {:error, reason}
        end
    end
  end

  defp to_text(value) when is_binary(value), do: value
  defp to_text(value), do: inspect(value)

  defp encode_converge_result(result) do
    result
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  defp replay_converge_result(%{status: "ok", result: encoded}) do
    encoded
    |> Base.decode64!()
    |> :erlang.binary_to_term()
    |> then(&{:ok, &1})
  end

  defp replay_converge_result(%{status: "error", result: reason}) do
    {:error, reason}
  end

  defp fetch_node(conn, node_id) do
    case Repo.get_node(conn, node_id) do
      nil -> {:error, "Node not found"}
      node -> {:ok, node}
    end
  end

  defp validate_converge_preconditions(:absent, [_ | _]), do: {:error, "Instance has peers"}
  defp validate_converge_preconditions(_action, _peers), do: :ok

  defp fetch_instance_and_node(conn, instance_id) do
    case Repo.get_instance(conn, instance_id) do
      nil ->
        nil

      %Instance{node_id: node_id} = instance ->
        case Repo.get_node(conn, node_id) do
          nil -> {:error, "Node not found for instance"}
          node -> {:ok, instance, node}
        end
    end
  end

  defp persist_target_state(_conn, _instance, _action, true), do: :ok

  defp persist_target_state(conn, instance, action, false) do
    case Instance.target_state_for_action(action) do
      :up -> Repo.update_instance_target_state(conn, instance.id, :up)
      :down -> Repo.update_instance_target_state(conn, instance.id, :down)
      nil -> delete_instance_record(conn, instance.id)
    end
  end

  defp delete_instance_record(conn, instance_id) do
    case Repo.list_peers(conn, instance_id) do
      [] -> Repo.delete_instance(conn, instance_id)
      [_ | _] -> {:error, "Instance has peers"}
    end
  end

  defp build_instance(state, node, attrs) do
    instance_id = attrs[:id]

    case Repo.get_instance(state.conn, instance_id) do
      nil -> build_new_instance(state, node, attrs)
      existing -> validate_existing_instance(state, node, existing, attrs)
    end
  end

  defp build_new_instance(state, node, attrs) do
    protocol = attrs[:protocol]
    instance_id = attrs[:id]

    with {:ok, awg_params} <- build_awg_params(protocol, attrs[:awg_params]),
         {:ok, public_key} <- state.agent_adapter.generate_keypair(node, instance_id, protocol) do
      instance = %Instance{
        id: instance_id,
        node_id: node.id,
        name: attrs[:name],
        protocol: protocol,
        listen_port: attrs[:listen_port],
        subnet: attrs[:subnet],
        private_key: nil,
        public_key: public_key,
        address: attrs[:address],
        dns: attrs[:dns],
        mtu: attrs[:mtu],
        awg_params: awg_params,
        target_state: :configured
      }

      {:ok, instance, :new}
    end
  end

  defp build_awg_params(:awg, nil), do: {:error, "AWG params are required"}

  defp build_awg_params(:awg, params) do
    params = struct(Instance.AWGParams, params)

    case AWGParamsValidator.validate(params) do
      :ok -> {:ok, params}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_awg_params(:wg, _), do: {:ok, nil}

  defp validate_existing_instance(state, node, existing, attrs) do
    protocol = attrs[:protocol]

    cond do
      existing.node_id != node.id ->
        {:error, "Instance already exists on another node"}

      existing.protocol != protocol ->
        {:error, "Instance protocol mismatch"}

      true ->
        stored_public_key = existing.public_key

        case state.agent_adapter.generate_keypair(node, attrs[:id], protocol) do
          {:ok, ^stored_public_key} -> {:ok, existing, :existing}
          {:ok, _other} -> {:error, "Instance public key mismatch"}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp maybe_insert_instance(_conn, _instance, :existing), do: :ok
  defp maybe_insert_instance(conn, instance, :new), do: Repo.insert_instance(conn, instance)

  defp build_peer(attrs, keys, psk) do
    %Peer{
      id: attrs[:id],
      instance_id: attrs[:instance_id],
      name: attrs[:name],
      private_key: keys.private_key,
      public_key: keys.public_key,
      preshared_key: psk,
      allowed_ips: attrs[:allowed_ips],
      persistent_keepalive: attrs[:persistent_keepalive],
      endpoint: attrs[:endpoint],
      address: attrs[:address],
      dns: attrs[:dns]
    }
  end

  defp node_status(node, adapter) do
    case adapter.status(node) do
      {:ok, agent_status} ->
        %Status{
          node_id: node.id,
          node_name: node.name,
          online: true,
          last_contact: agent_status.timestamp,
          agent_status: agent_status
        }

      {:error, _reason} ->
        %Status{
          node_id: node.id,
          node_name: node.name,
          online: false,
          last_contact: nil,
          agent_status: nil
        }
    end
  end
end
