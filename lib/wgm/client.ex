defmodule WGM.Client do
  @moduledoc """
  Тонкий клиент для управления WG/AWG-VPN из `iex` на ноутбуке.

  Подключается к контроллеру по Erlang distribution и предоставляет
  статус узлов/инстансов/пиров, а также операции чтения желаемого состояния.

  Пример использования в `iex`:

      iex> {:ok, ctrl} = WGM.Client.connect("wgm_controller@5.129.219.31", "my-cookie")
      iex> WGM.Client.status(ctrl)
      iex> WGM.Client.list_instances(ctrl)

  """

  @default_controller :wgm_controller

  @doc """
  Подключается к контроллеру.

  `controller_node` — имя ноды контроллера (`"wgm_controller@<ip>"`).
  `cookie` — общий Erlang-cookie (строка).

  Возвращает `{:ok, node}`, если distribution включён и нода доступна.
  """
  @spec connect(String.t() | atom(), String.t()) :: {:ok, node()} | {:error, String.t()}
  def connect(controller_node, cookie) do
    node = normalize_node(controller_node)

    with :ok <- ensure_distribution(),
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
    call_controller_unwrapped(controller_node, WGM.Controller, :create_peer, [
      @default_controller,
      command_id,
      attrs
    ])
  end

  @doc """
  Удаляет пира с контроллера.
  """
  @spec delete_peer(node(), String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def delete_peer(controller_node, command_id, peer_id) do
    call_controller_unwrapped(controller_node, WGM.Controller, :delete_peer, [
      @default_controller,
      command_id,
      peer_id
    ])
  end

  @doc """
  Генерирует и сохраняет клиентский конфиг пира.
  """
  @spec store_client_config(node(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_client_config(controller_node, command_id, peer_id, endpoint) do
    call_controller_unwrapped(controller_node, WGM.Controller, :store_client_config, [
      @default_controller,
      command_id,
      peer_id,
      endpoint
    ])
  end

  @doc """
  Возвращает ранее сохранённый клиентский конфиг пира.
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
  """
  @spec write_client_config(node(), String.t(), String.t()) ::
          :ok | {:error, String.t()}
  def write_client_config(controller_node, peer_id, path) do
    with {:ok, config} <- get_client_config(controller_node, peer_id) do
      File.write(path, config)
    end
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
      {:ok, ctrl} = WGM.Client.connect("wgm_controller@<ip>", "<cookie>")

    Команды:
      WGM.Client.status(ctrl)                   # статус всех узлов
      WGM.Client.list_nodes(ctrl)               # список узлов
      WGM.Client.list_instances(ctrl)           # список инстансов
      WGM.Client.list_peers(ctrl)               # список пиров
      WGM.Client.get_peer(ctrl, "peer-id")      # пир по id
      WGM.Client.create_peer(ctrl, "cmd-id", %{id: ..., instance_id: ..., name: ...})
      WGM.Client.delete_peer(ctrl, "cmd-id", "peer-id")
      WGM.Client.store_client_config(ctrl, "cmd-id", "peer-id", "endpoint:port")
      WGM.Client.get_client_config(ctrl, "peer-id")
      WGM.Client.write_client_config(ctrl, "peer-id", "/path/to/file.conf")
      WGM.Client.show_client_config_qr(ctrl, "peer-id")
      WGM.Client.help()                         # эта справка

    Требования: iex должен быть запущен с --name/--sname и --cookie,
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
  defp call_controller_unwrapped(node, module, function, args) do
    case call_controller(node, module, function, args) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, reason}} -> {:error, reason}
      other -> other
    end
  end
end
