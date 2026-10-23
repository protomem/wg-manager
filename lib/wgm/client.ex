defmodule WGM.Client do
  @moduledoc """
  Тонкий клиент для управления WG/AWG-VPN из `iex` на ноутбуке.

  Подключается к контроллеру по Erlang distribution и предоставляет
  статус узлов/инстансов/пиров, а также операции чтения желаемого состояния.

  Пример использования в `iex` (нода клиента обязательно hidden):

      $ iex --sname wgm_client --hidden --cookie my-cookie -S mix
      iex> {:ok, ctrl} = WGM.Client.connect("wgm_controller@5.129.219.31", "my-cookie")
      iex> WGM.Client.status(ctrl)
      iex> WGM.Client.list_instances(ctrl)

  """

  @default_controller :wgm_controller

  @doc """
  Подключается к контроллеру.

  `controller_node` — имя ноды контроллера (`"wgm_controller@<ip>"`).
  `cookie` — общий Erlang-cookie (строка).

  Требования: локальная нода должна быть запущена в hidden-режиме, например:

      iex --sname <name> --hidden --cookie <cookie> -S mix

  Если нода не hidden, возвращает `{:error, ...}` с инструкцией.
  Возвращает `{:ok, node}`, если distribution включён, нода hidden и контроллер доступен.
  """
  @spec connect(String.t() | atom(), String.t()) :: {:ok, node()} | {:error, String.t()}
  def connect(controller_node, cookie) do
    node = normalize_node(controller_node)

    with :ok <- ensure_distribution(),
         :ok <- ensure_hidden(),
         :ok <- set_cookie(node, cookie),
         true <- Node.connect(node) do
      {:ok, node}
    else
      false -> {:error, "Node #{node} is not reachable"}
      :ignored -> {:error, "Erlang distribution is not enabled"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Возвращает агрегированный статус всех зарегистрированных узлов.

  Результат содержит онлайн/офлайн состояние, время последнего контакта
  и статус агента (инстансы, пиры, интерфейсы).
  """
  @spec status(node()) :: {:ok, [WGM.Controller.Status.t()]} | {:error, String.t()}
  def status(controller_node) do
    call_controller(controller_node, WGM.Controller, :status, [@default_controller])
  end

  @doc """
  Возвращает список узлов из желаемого состояния контроллера.
  """
  @spec list_nodes(node()) :: {:ok, [WGM.Node.t()]} | {:error, String.t()}
  def list_nodes(controller_node) do
    call_controller(controller_node, WGM.Controller, :list_nodes, [@default_controller])
  end

  @doc """
  Возвращает список инстансов из желаемого состояния контроллера.
  """
  @spec list_instances(node()) :: {:ok, [WGM.Instance.t()]} | {:error, String.t()}
  def list_instances(controller_node) do
    call_controller(controller_node, WGM.Controller, :list_instances, [@default_controller])
  end

  @doc """
  Возвращает список пиров из желаемого состояния контроллера.
  """
  @spec list_peers(node()) :: {:ok, [WGM.Peer.t()]} | {:error, String.t()}
  def list_peers(controller_node) do
    call_controller(controller_node, WGM.Controller, :list_peers, [@default_controller])
  end

  @doc """
  Возвращает пира по идентификатору.
  """
  @spec get_peer(node(), String.t()) :: {:ok, WGM.Peer.t() | nil} | {:error, String.t()}
  def get_peer(controller_node, peer_id) do
    call_controller(controller_node, WGM.Controller, :get_peer, [@default_controller, peer_id])
  end

  @doc """
  Создаёт пира в инстансе на контроллере.
  """
  @spec create_peer(node(), String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def create_peer(controller_node, command_id, attrs) do
    call_controller_result(controller_node, WGM.Controller, :create_peer, [
      @default_controller,
      command_id,
      attrs
    ])
  end

  @doc """
  Удаляет пира с контроллера.

  Деструктивная операция: требует явного `confirm: true`.
  """
  @spec delete_peer(node(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def delete_peer(controller_node, command_id, peer_id, opts \\ []) do
    if Keyword.get(opts, :confirm, false) do
      call_controller_result(controller_node, WGM.Controller, :delete_peer, [
        @default_controller,
        command_id,
        peer_id
      ])
    else
      {:error, "Destructive action delete_peer requires confirmation"}
    end
  end

  @doc """
  Генерирует и сохраняет клиентский конфиг пира.

  Возвращаемая строка содержит приватный ключ; не выводите её в логи/терминал
  и не передавайте в `inspect` без необходимости.
  """
  @spec store_client_config(node(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_client_config(controller_node, command_id, peer_id, endpoint) do
    call_controller_result(controller_node, WGM.Controller, :store_client_config, [
      @default_controller,
      command_id,
      peer_id,
      endpoint
    ])
  end

  @doc """
  Возвращает ранее сохранённый клиентский конфиг пира.

  Возвращаемая строка содержит приватный ключ; не выводите её в логи/терминал
  и не передавайте в `inspect` без необходимости.
  """
  @spec get_client_config(node(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_client_config(controller_node, peer_id) do
    case call_controller(controller_node, WGM.Controller, :get_client_config, [
           @default_controller,
           peer_id
         ]) do
      {:ok, nil} -> {:error, "Client config not found"}
      other -> other
    end
  end

  @doc """
  Записывает сохранённый клиентский конфиг пира в файл.

  Временный файл создаётся с правами `0o600` ещё в момент открытия,
  в него записывается содержимое, после чего выполняется атомарный rename
  в целевой путь. При ошибке временный файл удаляется.
  """
  @spec write_client_config(node(), String.t(), String.t()) ::
          :ok | {:error, String.t()}
  def write_client_config(controller_node, peer_id, path) do
    with {:ok, config} <- get_client_config(controller_node, peer_id),
         :ok <- write_file_private(path, config) do
      :ok
    end
  end

  @doc false
  def write_file_private(path, content, rename_fn \\ &File.rename/2) do
    dir = Path.dirname(path)
    tmp_path = Path.join(dir, ".#{Path.basename(path)}.#{System.unique_integer([:positive])}.tmp")

    case :file.open(tmp_path, [:write, :exclusive, :binary, {:mode, 0o600}]) do
      {:ok, device} ->
        try do
          with :ok <- File.chmod(tmp_path, 0o600),
               :ok <- IO.write(device, content),
               :ok <- :file.close(device),
               :ok <- rename_fn.(tmp_path, path) do
            :ok
          else
            {:error, reason} when is_atom(reason) ->
              cleanup_tmp(tmp_path)
              {:error, to_string(:file.format_error(reason))}

            error ->
              cleanup_tmp(tmp_path)
              error
          end
        catch
          kind, reason ->
            :erlang.raise(kind, reason, __STACKTRACE__)
        after
          _ = :file.close(device)
        end

      {:error, reason} ->
        {:error, to_string(:file.format_error(reason))}
    end
  end

  defp cleanup_tmp(tmp_path) do
    _ = File.rm(tmp_path)
    :ok
  end

  @doc """
  Показывает QR-код клиентского конфига пира в терминале.
  """
  @spec show_client_config_qr(node(), String.t()) :: :ok | {:error, String.t()}
  def show_client_config_qr(controller_node, peer_id) do
    with {:ok, config} <- get_client_config(controller_node, peer_id) do
      config
      |> EQRCode.encode()
      |> EQRCode.render()
    end
  end

  @doc """
  Возвращает краткую справку по командам клиента.
  """
  @spec help() :: String.t()
  def help do
    """
    WGM.Client — iex-клиент управления WG/AWG-VPN.

    Подключение:
      iex --sname <name> --hidden --cookie <cookie> -S mix
      {:ok, ctrl} = WGM.Client.connect("wgm_controller@<ip>", "<cookie>")

    Команды:
      WGM.Client.status(ctrl)                   # статус всех узлов
      WGM.Client.list_nodes(ctrl)               # список узлов
      WGM.Client.list_instances(ctrl)           # список инстансов
      WGM.Client.list_peers(ctrl)               # список пиров
      WGM.Client.get_peer(ctrl, "peer-id")      # пир по id
      WGM.Client.create_peer(ctrl, "cmd-id", %{id: ..., instance_id: ..., name: ...})
      WGM.Client.delete_peer(ctrl, "cmd-id", "peer-id", confirm: true)
      WGM.Client.store_client_config(ctrl, "cmd-id", "peer-id", "endpoint:port")
      WGM.Client.get_client_config(ctrl, "peer-id")
      WGM.Client.write_client_config(ctrl, "peer-id", "/path/to/file.conf")
      WGM.Client.show_client_config_qr(ctrl, "peer-id")
      WGM.Client.help()                         # эта справка

    Требования: iex должен быть запущен с --name/--sname, --cookie и --hidden,
    либо distribution включён до вызова connect/2.
    """
  end

  defp normalize_node(node) when is_atom(node), do: node
  defp normalize_node(node) when is_binary(node), do: String.to_atom(node)

  defp ensure_distribution do
    if Node.self() == :nonode@nohost do
      {:error, "Erlang distribution is not enabled"}
    else
      :ok
    end
  end

  defp ensure_hidden do
    if :net_kernel.publish_on_node(Node.self()) do
      {:error,
       "Client node must be started in hidden mode. " <>
         "Run: iex --sname <name> --hidden --cookie <cookie> -S mix"}
    else
      :ok
    end
  end

  defp set_cookie(node, cookie) do
    cookie_atom = String.to_atom(cookie)

    case Node.set_cookie(node, cookie_atom) do
      true -> :ok
      :ignored -> {:error, "Erlang distribution is not enabled"}
    end
  end

  defp call_controller(node, module, function, args) do
    try do
      result =
        if node == Node.self() do
          apply(module, function, args)
        else
          :erpc.call(node, module, function, args, 5_000)
        end

      {:ok, result}
    catch
      kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
    end
  end

  # Для RPC-вызовов, которые сами возвращают {:ok, ...} или {:error, ...}.
  defp call_controller_result(node, module, function, args) do
    case call_controller(node, module, function, args) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, reason}} -> {:error, reason}
      other -> other
    end
  end
end
