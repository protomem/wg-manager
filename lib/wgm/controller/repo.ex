defmodule WGM.Controller.Repo do
  @moduledoc """
  Raw Exqlite-хранилище желаемого состояния контроллера.
  """

  alias Exqlite.Sqlite3
  alias WGM.{Cascade, Instance, Node, Peer}
  alias WGM.Instance.AWGParams

  @spec open(String.t()) :: {:ok, Sqlite3.db()} | {:error, Sqlite3.reason()}
  def open(path \\ ":memory:") do
    with {:ok, conn} <- Sqlite3.open(path) do
      _ = ensure_db_permissions(path)
      {:ok, conn}
    end
  end

  defp ensure_db_permissions(":memory:"), do: :ok

  defp ensure_db_permissions(path) do
    # БД содержит клиентские конфиги с приватными ключами; файл должен быть
    # доступен только владельцу (root). См. спеку «Секреты».
    case File.chmod(path, 0o600) do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec migrate(Sqlite3.db()) :: :ok | {:error, Sqlite3.reason()}
  def migrate(conn) do
    with :ok <- Sqlite3.execute(conn, schema()),
         :ok <- add_instance_state_column(conn),
         :ok <- add_node_last_contact_column(conn),
         :ok <- create_check_results_table(conn),
         :ok <- create_cascades_table(conn),
         :ok <- add_instance_post_columns(conn),
         :ok <- add_cascade_target_column(conn),
         :ok <- relax_peer_private_key_constraint(conn) do
      :ok
    end
  end

  # Nodes

  @spec insert_node(Sqlite3.db(), Node.t()) :: :ok | {:error, Sqlite3.reason()}
  def insert_node(conn, %Node{} = node) do
    now = now()

    execute(
      conn,
      """
      INSERT INTO nodes (id, name, address, role, description, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        node.id,
        node.name,
        node.address,
        to_string(node.role),
        node.description,
        now,
        now
      ]
    )
  end

  @spec list_nodes(Sqlite3.db()) :: [Node.t()]
  def list_nodes(conn) do
    conn
    |> query(
      "SELECT id, name, address, role, description, inserted_at, updated_at FROM nodes ORDER BY name"
    )
    |> Enum.map(&row_to_node/1)
  end

  @spec get_node(Sqlite3.db(), String.t()) :: Node.t() | nil
  def get_node(conn, id) do
    conn
    |> query_one(
      "SELECT id, name, address, role, description, inserted_at, updated_at FROM nodes WHERE id = ?",
      [id]
    )
    |> then(&(&1 && row_to_node(&1)))
  end

  @spec delete_node(Sqlite3.db(), String.t()) :: :ok | {:error, Sqlite3.reason()}
  def delete_node(conn, id) do
    execute(conn, "DELETE FROM nodes WHERE id = ?", [id])
  end

  # Instances

  @spec insert_instance(Sqlite3.db(), Instance.t()) :: :ok | {:error, Sqlite3.reason()}
  def insert_instance(conn, %Instance{} = instance) do
    now = now()
    awg = instance.awg_params

    execute(
      conn,
      """
      INSERT INTO instances (
        id, node_id, name, protocol, listen_port, subnet,
        private_key, public_key, address, dns, mtu,
        jc, jmin, jmax, s1, s2, s3, s4,
        h1, h2, h3, h4, i1, i2, i3, i4, i5,
        header_protection_key, post_up, post_down, state, inserted_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        instance.id,
        instance.node_id,
        instance.name,
        to_string(instance.protocol),
        instance.listen_port,
        instance.subnet,
        instance.private_key,
        instance.public_key,
        instance.address,
        instance.dns,
        instance.mtu,
        awg && awg.jc,
        awg && awg.jmin,
        awg && awg.jmax,
        awg && awg.s1,
        awg && awg.s2,
        awg && awg.s3,
        awg && awg.s4,
        awg && awg.h1,
        awg && awg.h2,
        awg && awg.h3,
        awg && awg.h4,
        awg && awg.i1,
        awg && awg.i2,
        awg && awg.i3,
        awg && awg.i4,
        awg && awg.i5,
        awg && awg.header_protection_key,
        join_commands(instance.post_up),
        join_commands(instance.post_down),
        to_string(instance.target_state || :configured),
        now,
        now
      ]
    )
  end

  @spec list_instances(Sqlite3.db()) :: [Instance.t()]
  def list_instances(conn) do
    conn
    |> query(instance_select())
    |> Enum.map(&row_to_instance/1)
  end

  @spec list_instances(Sqlite3.db(), String.t()) :: [Instance.t()]
  def list_instances(conn, node_id) do
    conn
    |> query(instance_select() <> " WHERE node_id = ? ORDER BY name", [node_id])
    |> Enum.map(&row_to_instance/1)
  end

  @spec get_instance(Sqlite3.db(), String.t()) :: Instance.t() | nil
  def get_instance(conn, id) do
    conn
    |> query_one(instance_select() <> " WHERE id = ?", [id])
    |> then(&(&1 && row_to_instance(&1)))
  end

  @spec delete_instance(Sqlite3.db(), String.t()) :: :ok | {:error, Sqlite3.reason()}
  def delete_instance(conn, id) do
    execute(conn, "DELETE FROM instances WHERE id = ?", [id])
  end

  @spec update_instance(Sqlite3.db(), Instance.t()) :: :ok | {:error, Sqlite3.reason()}
  def update_instance(conn, %Instance{} = instance) do
    awg = instance.awg_params

    execute(
      conn,
      """
      UPDATE instances SET
        protocol = ?, listen_port = ?, subnet = ?, public_key = ?, address = ?, dns = ?, mtu = ?,
        jc = ?, jmin = ?, jmax = ?, s1 = ?, s2 = ?, s3 = ?, s4 = ?,
        h1 = ?, h2 = ?, h3 = ?, h4 = ?, i1 = ?, i2 = ?, i3 = ?, i4 = ?, i5 = ?,
        header_protection_key = ?, post_up = ?, post_down = ?, state = ?, updated_at = ?
      WHERE id = ?
      """,
      [
        to_string(instance.protocol),
        instance.listen_port,
        instance.subnet,
        instance.public_key,
        instance.address,
        instance.dns,
        instance.mtu,
        awg && awg.jc,
        awg && awg.jmin,
        awg && awg.jmax,
        awg && awg.s1,
        awg && awg.s2,
        awg && awg.s3,
        awg && awg.s4,
        awg && awg.h1,
        awg && awg.h2,
        awg && awg.h3,
        awg && awg.h4,
        awg && awg.i1,
        awg && awg.i2,
        awg && awg.i3,
        awg && awg.i4,
        awg && awg.i5,
        awg && awg.header_protection_key,
        join_commands(instance.post_up),
        join_commands(instance.post_down),
        to_string(instance.target_state || :configured),
        now(),
        instance.id
      ]
    )
  end

  # DB-столбец оставлен `state` для совместимости существующих баз;
  # в Elixir-коде это `Instance.target_state`.
  @spec update_instance_target_state(Sqlite3.db(), String.t(), Instance.target_state()) ::
          :ok | {:error, Sqlite3.reason()}
  def update_instance_target_state(conn, id, target_state) do
    execute(
      conn,
      "UPDATE instances SET state = ?, updated_at = ? WHERE id = ?",
      [to_string(target_state), now(), id]
    )
  end

  # Peers

  @spec insert_peer(Sqlite3.db(), Peer.t()) :: :ok | {:error, Sqlite3.reason()}
  def insert_peer(conn, %Peer{} = peer) do
    now = now()

    execute(
      conn,
      """
      INSERT INTO peers (
        id, instance_id, name, private_key, public_key, preshared_key,
        allowed_ips, persistent_keepalive, endpoint, address, dns,
        inserted_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        peer.id,
        peer.instance_id,
        peer.name,
        peer.private_key,
        peer.public_key,
        peer.preshared_key,
        peer.allowed_ips,
        peer.persistent_keepalive,
        peer.endpoint,
        peer.address,
        peer.dns,
        now,
        now
      ]
    )
  end

  @spec list_peers(Sqlite3.db()) :: [Peer.t()]
  def list_peers(conn) do
    conn
    |> query(peer_select())
    |> Enum.map(&row_to_peer/1)
  end

  @spec list_peers(Sqlite3.db(), String.t()) :: [Peer.t()]
  def list_peers(conn, instance_id) do
    conn
    |> query(peer_select() <> " WHERE instance_id = ? ORDER BY name", [instance_id])
    |> Enum.map(&row_to_peer/1)
  end

  @spec get_peer(Sqlite3.db(), String.t()) :: Peer.t() | nil
  def get_peer(conn, id) do
    conn
    |> query_one(peer_select() <> " WHERE id = ?", [id])
    |> then(&(&1 && row_to_peer(&1)))
  end

  @spec delete_peer(Sqlite3.db(), String.t()) :: :ok | {:error, Sqlite3.reason()}
  def delete_peer(conn, id) do
    with :ok <- execute(conn, "DELETE FROM client_configs WHERE peer_id = ?", [id]) do
      execute(conn, "DELETE FROM peers WHERE id = ?", [id])
    end
  end

  # Client configs

  @spec upsert_client_config(Sqlite3.db(), String.t(), String.t()) ::
          :ok | {:error, Sqlite3.reason()}
  def upsert_client_config(conn, peer_id, config) do
    now = now()

    execute(
      conn,
      """
      INSERT INTO client_configs (peer_id, config, inserted_at, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(peer_id) DO UPDATE SET
        config = excluded.config,
        updated_at = excluded.updated_at
      """,
      [peer_id, config, now, now]
    )
  end

  @spec get_client_config(Sqlite3.db(), String.t()) :: String.t() | nil
  def get_client_config(conn, peer_id) do
    conn
    |> query_one(
      "SELECT peer_id, config, inserted_at, updated_at FROM client_configs WHERE peer_id = ?",
      [peer_id]
    )
    |> then(fn
      nil -> nil
      [_, config, _, _] -> config
    end)
  end

  @spec delete_client_config(Sqlite3.db(), String.t()) :: :ok | {:error, Sqlite3.reason()}
  def delete_client_config(conn, peer_id) do
    execute(conn, "DELETE FROM client_configs WHERE peer_id = ?", [peer_id])
  end

  # Command journal

  @spec log_command(Sqlite3.db(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, Sqlite3.reason()}
  def log_command(conn, command_id, type, object_id, status, result) do
    execute(
      conn,
      """
      INSERT INTO command_journal (command_id, type, object_id, status, result, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      [command_id, type, object_id, status, result, now()]
    )
  end

  @spec get_command(Sqlite3.db(), String.t()) :: map() | nil
  def get_command(conn, command_id) do
    conn
    |> query_one(
      "SELECT command_id, type, object_id, status, result, created_at FROM command_journal WHERE command_id = ?",
      [command_id]
    )
    |> then(&(&1 && row_to_command(&1)))
  end

  @spec list_commands(Sqlite3.db()) :: [map()]
  def list_commands(conn) do
    conn
    |> query(
      "SELECT command_id, type, object_id, status, result, created_at FROM command_journal ORDER BY created_at"
    )
    |> Enum.map(&row_to_command/1)
  end

  # Audit log

  @spec append_audit(
          Sqlite3.db(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) ::
          :ok | {:error, Sqlite3.reason()}
  def append_audit(conn, command_id, type, object_id, initiator, result, summary) do
    execute(
      conn,
      """
      INSERT INTO audit_log (command_id, type, object_id, initiator, result, summary, timestamp)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [command_id, type, object_id, initiator, result, summary, now()]
    )
  end

  @spec list_audit(Sqlite3.db()) :: [map()]
  def list_audit(conn) do
    conn
    |> query(
      "SELECT id, command_id, type, object_id, initiator, result, summary, timestamp FROM audit_log ORDER BY id"
    )
    |> Enum.map(&row_to_audit/1)
  end

  # Node last contact

  @spec update_node_last_contact(Sqlite3.db(), String.t(), DateTime.t()) ::
          :ok | {:error, Sqlite3.reason()}
  def update_node_last_contact(conn, node_id, last_contact) do
    execute(
      conn,
      "UPDATE nodes SET last_contact = ? WHERE id = ?",
      [DateTime.to_iso8601(last_contact), node_id]
    )
  end

  @spec get_node_last_contact(Sqlite3.db(), String.t()) :: DateTime.t() | nil
  def get_node_last_contact(conn, node_id) do
    conn
    |> query_one(
      "SELECT last_contact FROM nodes WHERE id = ?",
      [node_id]
    )
    |> then(fn
      nil -> nil
      [nil] -> nil
      [value] -> from_iso(value)
    end)
  end

  # Check results

  @spec insert_check_result(Sqlite3.db(), WGM.Check.Result.t()) ::
          :ok | {:error, Sqlite3.reason()}
  def insert_check_result(conn, %WGM.Check.Result{} = result) do
    execute(
      conn,
      """
      INSERT INTO check_results (
        node_id, instance_id, peer_id, kind, status, detail,
        checked_at, last_success_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        result.node_id,
        result.instance_id,
        result.peer_id,
        to_string(result.kind),
        to_string(result.status),
        result.detail,
        DateTime.to_iso8601(result.checked_at),
        maybe_iso(result.last_success_at)
      ]
    )
  end

  @spec list_latest_check_results(Sqlite3.db(), keyword()) :: [WGM.Check.Result.t()]
  def list_latest_check_results(conn, opts \\ []) do
    node_filter = opts[:node_id]
    instance_filter = opts[:instance_id]

    base_sql = """
    SELECT
      node_id, instance_id, peer_id, kind, status, detail,
      checked_at, last_success_at
    FROM check_results cr
    WHERE checked_at = (
      SELECT MAX(checked_at)
      FROM check_results cr2
      WHERE cr2.node_id = cr.node_id
        AND COALESCE(cr2.instance_id, '') = COALESCE(cr.instance_id, '')
        AND COALESCE(cr2.peer_id, '') = COALESCE(cr.peer_id, '')
        AND cr2.kind = cr.kind
    )
    """

    {sql, params} =
      {base_sql, []}
      |> maybe_filter(" AND cr.node_id = ?", node_filter)
      |> maybe_filter(" AND cr.instance_id = ?", instance_filter)

    conn
    |> query(sql <> " ORDER BY cr.node_id, cr.instance_id, cr.kind, cr.peer_id", params)
    |> Enum.map(&row_to_check_result/1)
  end

  defp maybe_filter({sql, params}, _clause, nil), do: {sql, params}

  defp maybe_filter({sql, params}, clause, value) do
    {sql <> clause, params ++ [value]}
  end

  @spec latest_successful_check(
          Sqlite3.db(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          atom()
        ) :: DateTime.t() | nil
  def latest_successful_check(conn, node_id, instance_id, peer_id, kind) do
    conn
    |> query_one(
      """
      SELECT MAX(checked_at)
      FROM check_results
      WHERE node_id = ?
        AND COALESCE(instance_id, '') = ?
        AND COALESCE(peer_id, '') = ?
        AND kind = ?
        AND status = 'ok'
      """,
      [node_id, instance_id || "", peer_id || "", to_string(kind)]
    )
    |> then(fn
      nil -> nil
      [nil] -> nil
      [value] -> from_iso(value)
    end)
  end

  # Schema

  defp schema do
    """
    CREATE TABLE IF NOT EXISTS nodes (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      address TEXT NOT NULL,
      role TEXT NOT NULL,
      description TEXT,
      last_contact TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS instances (
      id TEXT PRIMARY KEY,
      node_id TEXT NOT NULL,
      name TEXT NOT NULL,
      protocol TEXT NOT NULL,
      listen_port INTEGER NOT NULL,
      subnet TEXT NOT NULL,
      private_key TEXT,
      public_key TEXT NOT NULL,
      address TEXT NOT NULL,
      dns TEXT,
      mtu INTEGER,
      jc INTEGER,
      jmin INTEGER,
      jmax INTEGER,
      s1 INTEGER,
      s2 INTEGER,
      s3 INTEGER,
      s4 INTEGER,
      h1 TEXT,
      h2 TEXT,
      h3 TEXT,
      h4 TEXT,
      i1 INTEGER,
      i2 INTEGER,
      i3 INTEGER,
      i4 INTEGER,
      i5 INTEGER,
      header_protection_key TEXT,
      post_up TEXT,
      post_down TEXT,
      state TEXT NOT NULL DEFAULT 'configured',
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS peers (
      id TEXT PRIMARY KEY,
      instance_id TEXT NOT NULL,
      name TEXT NOT NULL,
      private_key TEXT,
      public_key TEXT NOT NULL,
      preshared_key TEXT,
      allowed_ips TEXT NOT NULL,
      persistent_keepalive TEXT,
      endpoint TEXT,
      address TEXT,
      dns TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS client_configs (
      peer_id TEXT PRIMARY KEY,
      config TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS command_journal (
      command_id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      object_id TEXT NOT NULL,
      status TEXT NOT NULL,
      result TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      command_id TEXT NOT NULL,
      type TEXT NOT NULL,
      object_id TEXT NOT NULL,
      initiator TEXT NOT NULL,
      result TEXT NOT NULL,
      summary TEXT NOT NULL,
      timestamp TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS check_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      node_id TEXT NOT NULL,
      instance_id TEXT,
      peer_id TEXT,
      kind TEXT NOT NULL,
      status TEXT NOT NULL,
      detail TEXT,
      checked_at TEXT NOT NULL,
      last_success_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_check_results_lookup
      ON check_results (node_id, instance_id, peer_id, kind, checked_at);

    CREATE TABLE IF NOT EXISTS cascades (
      id TEXT PRIMARY KEY,
      entry_instance_id TEXT NOT NULL,
      entry_transit_instance_id TEXT,
      exit_instance_id TEXT NOT NULL,
      name TEXT,
      target TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    """
  end

  defp add_instance_state_column(conn) do
    columns =
      query(conn, "PRAGMA table_info(instances)")
      |> Enum.map(fn [_cid, name, _type, _notnull, _dflt, _pk] -> name end)

    if "state" in columns do
      :ok
    else
      execute(
        conn,
        "ALTER TABLE instances ADD COLUMN state TEXT NOT NULL DEFAULT 'configured'",
        []
      )
    end
  end

  defp add_node_last_contact_column(conn) do
    columns =
      query(conn, "PRAGMA table_info(nodes)")
      |> Enum.map(fn [_cid, name, _type, _notnull, _dflt, _pk] -> name end)

    if "last_contact" in columns do
      :ok
    else
      execute(conn, "ALTER TABLE nodes ADD COLUMN last_contact TEXT", [])
    end
  end

  defp create_check_results_table(conn) do
    tables =
      query(conn, "SELECT name FROM sqlite_master WHERE type = 'table'")
      |> Enum.map(fn [name] -> name end)

    if "check_results" in tables do
      :ok
    else
      Sqlite3.execute(conn, """
      CREATE TABLE check_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_id TEXT NOT NULL,
        instance_id TEXT,
        peer_id TEXT,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        detail TEXT,
        checked_at TEXT NOT NULL,
        last_success_at TEXT
      );

      CREATE INDEX idx_check_results_lookup
        ON check_results (node_id, instance_id, peer_id, kind, checked_at);
      """)
    end
  end

  defp create_cascades_table(conn) do
    tables =
      query(conn, "SELECT name FROM sqlite_master WHERE type = 'table'")
      |> Enum.map(fn [name] -> name end)

    if "cascades" in tables do
      :ok
    else
      Sqlite3.execute(conn, """
      CREATE TABLE cascades (
        id TEXT PRIMARY KEY,
        entry_instance_id TEXT NOT NULL,
        entry_transit_instance_id TEXT,
        exit_instance_id TEXT NOT NULL,
        name TEXT,
        target TEXT,
        inserted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      """)
    end
  end

  defp add_cascade_target_column(conn) do
    columns =
      query(conn, "PRAGMA table_info(cascades)")
      |> Enum.map(fn [_cid, name, _type, _notnull, _dflt, _pk] -> name end)

    unless "target" in columns do
      execute(conn, "ALTER TABLE cascades ADD COLUMN target TEXT", [])
    end

    unless "entry_transit_instance_id" in columns do
      execute(conn, "ALTER TABLE cascades ADD COLUMN entry_transit_instance_id TEXT", [])
    end

    :ok
  end

  defp relax_peer_private_key_constraint(conn) do
    columns =
      query(conn, "PRAGMA table_info(peers)")
      |> Enum.map(fn [_cid, name, _type, notnull, _dflt, _pk] -> {name, notnull} end)

    case List.keyfind(columns, "private_key", 0) do
      {"private_key", 1} ->
        Sqlite3.execute(conn, """
        ALTER TABLE peers RENAME TO peers_old;

        CREATE TABLE peers (
          id TEXT PRIMARY KEY,
          instance_id TEXT NOT NULL,
          name TEXT NOT NULL,
          private_key TEXT,
          public_key TEXT NOT NULL,
          preshared_key TEXT,
          allowed_ips TEXT NOT NULL,
          persistent_keepalive TEXT,
          endpoint TEXT,
          address TEXT,
          dns TEXT,
          inserted_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        INSERT INTO peers
        SELECT id, instance_id, name, private_key, public_key, preshared_key,
               allowed_ips, persistent_keepalive, endpoint, address, dns,
               inserted_at, updated_at
        FROM peers_old;

        DROP TABLE peers_old;
        """)

      _ ->
        :ok
    end
  end

  defp add_instance_post_columns(conn) do
    columns =
      query(conn, "PRAGMA table_info(instances)")
      |> Enum.map(fn [_cid, name, _type, _notnull, _dflt, _pk] -> name end)

    migrations = [
      {"post_up", "ALTER TABLE instances ADD COLUMN post_up TEXT"},
      {"post_down", "ALTER TABLE instances ADD COLUMN post_down TEXT"}
    ]

    Enum.each(migrations, fn {name, sql} ->
      unless name in columns do
        execute(conn, sql, [])
      end
    end)

    :ok
  end

  # Cascades

  @spec insert_cascade(Sqlite3.db(), Cascade.t()) :: :ok | {:error, Sqlite3.reason()}
  def insert_cascade(conn, %Cascade{} = cascade) do
    now = now()

    execute(
      conn,
      """
      INSERT INTO cascades (
        id, entry_instance_id, entry_transit_instance_id, exit_instance_id,
        name, target, inserted_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        cascade.id,
        cascade.entry_instance_id,
        cascade.entry_transit_instance_id,
        cascade.exit_instance_id,
        cascade.name,
        cascade.target,
        now,
        now
      ]
    )
  end

  @spec list_cascades(Sqlite3.db()) :: [Cascade.t()]
  def list_cascades(conn) do
    conn
    |> query(
      "SELECT id, entry_instance_id, entry_transit_instance_id, exit_instance_id, name, target FROM cascades ORDER BY name"
    )
    |> Enum.map(&row_to_cascade/1)
  end

  @spec get_cascade(Sqlite3.db(), String.t()) :: Cascade.t() | nil
  def get_cascade(conn, id) do
    conn
    |> query_one(
      "SELECT id, entry_instance_id, entry_transit_instance_id, exit_instance_id, name, target FROM cascades WHERE id = ?",
      [id]
    )
    |> then(&(&1 && row_to_cascade(&1)))
  end

  @spec delete_cascade(Sqlite3.db(), String.t()) :: :ok | {:error, Sqlite3.reason()}
  def delete_cascade(conn, id) do
    execute(conn, "DELETE FROM cascades WHERE id = ?", [id])
  end

  @spec update_cascade(Sqlite3.db(), Cascade.t()) :: :ok | {:error, Sqlite3.reason()}
  def update_cascade(conn, %Cascade{} = cascade) do
    execute(
      conn,
      """
      UPDATE cascades SET
        entry_transit_instance_id = ?, exit_instance_id = ?, name = ?, target = ?, updated_at = ?
      WHERE id = ?
      """,
      [
        cascade.entry_transit_instance_id,
        cascade.exit_instance_id,
        cascade.name,
        cascade.target,
        now(),
        cascade.id
      ]
    )
  end

  # Helpers

  defp instance_select do
    """
    SELECT
      id, node_id, name, protocol, listen_port, subnet,
      private_key, public_key, address, dns, mtu,
      jc, jmin, jmax, s1, s2, s3, s4,
      h1, h2, h3, h4, i1, i2, i3, i4, i5,
      header_protection_key, post_up, post_down, state, inserted_at, updated_at
    FROM instances
    """
  end

  defp peer_select do
    """
    SELECT
      id, instance_id, name, private_key, public_key, preshared_key,
      allowed_ips, persistent_keepalive, endpoint, address, dns,
      inserted_at, updated_at
    FROM peers
    """
  end

  defp row_to_node([id, name, address, role, description | _]) do
    %Node{
      id: id,
      name: name,
      address: address,
      role: to_atom(role),
      description: description
    }
  end

  defp row_to_instance([
         id,
         node_id,
         name,
         protocol,
         listen_port,
         subnet,
         private_key,
         public_key,
         address,
         dns,
         mtu,
         jc,
         jmin,
         jmax,
         s1,
         s2,
         s3,
         s4,
         h1,
         h2,
         h3,
         h4,
         i1,
         i2,
         i3,
         i4,
         i5,
         header_protection_key,
         post_up,
         post_down,
         state | _
       ]) do
    %Instance{
      id: id,
      node_id: node_id,
      name: name,
      protocol: to_atom(protocol),
      listen_port: listen_port,
      subnet: subnet,
      private_key: private_key,
      public_key: public_key,
      address: address,
      dns: dns,
      mtu: mtu,
      awg_params:
        awg_params(
          jc,
          jmin,
          jmax,
          s1,
          s2,
          s3,
          s4,
          h1,
          h2,
          h3,
          h4,
          i1,
          i2,
          i3,
          i4,
          i5,
          header_protection_key
        ),
      post_up: split_commands(post_up),
      post_down: split_commands(post_down),
      target_state: parse_state(state)
    }
  end

  defp awg_params(nil, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _), do: nil

  defp awg_params(
         jc,
         jmin,
         jmax,
         s1,
         s2,
         s3,
         s4,
         h1,
         h2,
         h3,
         h4,
         i1,
         i2,
         i3,
         i4,
         i5,
         header_protection_key
       ) do
    %AWGParams{
      jc: jc,
      jmin: jmin,
      jmax: jmax,
      s1: s1,
      s2: s2,
      s3: s3,
      s4: s4,
      h1: h1,
      h2: h2,
      h3: h3,
      h4: h4,
      i1: i1,
      i2: i2,
      i3: i3,
      i4: i4,
      i5: i5,
      header_protection_key: header_protection_key
    }
  end

  defp row_to_peer([
         id,
         instance_id,
         name,
         private_key,
         public_key,
         preshared_key,
         allowed_ips,
         persistent_keepalive,
         endpoint,
         address,
         dns | _
       ]) do
    %Peer{
      id: id,
      instance_id: instance_id,
      name: name,
      private_key: private_key,
      public_key: public_key,
      preshared_key: preshared_key,
      allowed_ips: allowed_ips,
      persistent_keepalive: persistent_keepalive,
      endpoint: endpoint,
      address: address,
      dns: dns
    }
  end

  defp row_to_command([command_id, type, object_id, status, result, created_at]) do
    %{
      command_id: command_id,
      type: type,
      object_id: object_id,
      status: status,
      result: result,
      created_at: from_iso(created_at)
    }
  end

  defp row_to_audit([id, command_id, type, object_id, initiator, result, summary, timestamp]) do
    %{
      id: id,
      command_id: command_id,
      type: type,
      object_id: object_id,
      initiator: initiator,
      result: result,
      summary: summary,
      timestamp: from_iso(timestamp)
    }
  end

  defp row_to_check_result([
         node_id,
         instance_id,
         peer_id,
         kind,
         status,
         detail,
         checked_at,
         last_success_at
       ]) do
    %WGM.Check.Result{
      node_id: node_id,
      instance_id: instance_id,
      peer_id: peer_id,
      kind: parse_kind(kind),
      status: parse_status(status),
      detail: detail,
      checked_at: from_iso(checked_at),
      last_success_at: from_iso(last_success_at)
    }
  end

  defp row_to_cascade([
         id,
         entry_instance_id,
         entry_transit_instance_id,
         exit_instance_id,
         name,
         target
       ]) do
    %Cascade{
      id: id,
      entry_instance_id: entry_instance_id,
      entry_transit_instance_id: entry_transit_instance_id,
      exit_instance_id: exit_instance_id,
      name: name,
      target: target
    }
  end

  defp maybe_iso(nil), do: nil
  defp maybe_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp join_commands(nil), do: nil
  defp join_commands([]), do: nil
  defp join_commands(commands) when is_list(commands), do: Enum.join(commands, "\n")

  defp split_commands(nil), do: nil

  defp split_commands(string) when is_binary(string) do
    string
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
  end

  defp execute(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          with :ok <- Sqlite3.bind(stmt, params) do
            case Sqlite3.step(conn, stmt) do
              :done -> :ok
              error -> error
            end
          end
        after
          Sqlite3.release(conn, stmt)
        end

      error ->
        error
    end
  end

  defp query(conn, sql, params \\ []) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          with :ok <- Sqlite3.bind(stmt, params),
               {:ok, rows} <- Sqlite3.fetch_all(conn, stmt, 1000) do
            rows
          else
            {:error, reason} -> raise "Query failed: #{reason}"
          end
        after
          Sqlite3.release(conn, stmt)
        end

      {:error, reason} ->
        raise "Query failed: #{reason}"
    end
  end

  defp query_one(conn, sql, params) do
    case query(conn, sql, params) do
      [row | _] -> row
      [] -> nil
    end
  end

  defp now do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp from_iso(nil), do: nil

  defp from_iso(string) do
    {:ok, dt, _} = DateTime.from_iso8601(string)
    dt
  end

  defp to_atom(string) when is_binary(string), do: String.to_atom(string)

  defp parse_state("up"), do: :up
  defp parse_state("down"), do: :down
  defp parse_state(_), do: :configured

  defp parse_kind(string) when is_binary(string), do: String.to_atom(string)

  defp parse_status("ok"), do: :ok
  defp parse_status("error"), do: :error
  defp parse_status("unknown"), do: :unknown
  defp parse_status(_), do: :unknown
end
