defmodule WGM.Cascade.Builder do
  @moduledoc """
  Генератор декларативного плана каскада вход→выход.

  ## Доктрина маршрутизации каскада

  Каскад состоит из трёх звеньев:

    1. **Ноутбук → entry WG-приёмник** (первый хоп).
       На серверной стороне (entry WG) peer ноутбука получает конкретный
       `AllowedIPs = <адрес ноутбука>/32`. Это предотвращает полнотуннельную
       маршрутизацию на entry-узле.

    2. **Entry AWG-транзит → exit AWG-приёмник** (второй хоп).
       Entry-транзит является клиентом этого туннеля: его peer в сторону exit
       имеет `AllowedIPs = 0.0.0.0/0`, чтобы перенаправлять в каскад весь
       трафик, который entry уже принял от ноутбука. Однако сам инстанс
       получает `Table = off`, поэтому `wg-quick` НЕ создаёт полнотуннельных
       правил в main-таблице. Вместо этого `PostUp` добавляет точечные
       policy-правила: трафик из подсети ноутбука (`from <laptop-subnet>`)
       направляется в отдельную таблицу маршрутизации, где default-шлюзом
       является туннельный интерфейс `%i`. `PreDown` симметрично удаляет эти
       правила.

    3. **Exit AWG-приёмник → интернет** (выходной NAT).
       На серверной стороне (exit AWG) peer entry-транзита получает
       `AllowedIPs = <laptop-subnet>,<entry-transit-address>/32`. Это
       разрешает обратный трафик к ноутбуку и к самому транзитному узлу.
       Exit выполняет NAT (`POSTROUTING -j MASQUERADE`) и включает
       `net.ipv4.ip_forward=1` через `PostUp`.

  В результате:

    - SSH-управление entry-узлом остаётся вне VPN-туннеля.
    - Только трафик из подсети ноутбука уходит в каскад.
    - Никакой серверный peer не содержит `AllowedIPs = 0.0.0.0/0`.
  """

  alias WGM.{Instance, Node}

  @type instance_plan :: %{
          entry_transit: map(),
          exit: map()
        }

  @type peer_plan :: %{
          entry_peer: map(),
          exit_peer: map()
        }

  @default_entry_transit_id "cascade-entry-transit"
  @default_entry_transit_name "awg-entry"
  @default_entry_transit_port 52_001
  @default_entry_transit_subnet "10.200.0.0/30"
  @default_entry_transit_address "10.200.0.1/30"

  @default_exit_id "cascade-exit"
  @default_exit_name "awg-exit"
  @default_exit_port 52_002
  @default_exit_subnet "10.200.1.0/24"
  @default_exit_address "10.200.1.1/24"

  @default_nat_interface "eth0"

  @doc """
  Возвращает атрибуты инстансов для каскада.

  Опции:
    - `:entry_transit_id`, `:entry_transit_name`, `:entry_transit_port`,
      `:entry_transit_subnet`, `:entry_transit_address`;
    - `:exit_id`, `:exit_name`, `:exit_port`, `:exit_subnet`, `:exit_address`;
    - `:nat_interface` — интерфейс для NAT-masquerade (по умолчанию `eth0`);
    - `:client_subnet` — подсеть ноутбука (`10.210.0.0/24`), трафик из которой
      будет направлен в каскад через policy-правила entry-транзита.
  """
  @spec plan_instances(Node.t(), Node.t(), keyword()) :: instance_plan()
  def plan_instances(%Node{} = entry_node, %Node{} = exit_node, opts \\ []) do
    nat_interface = Keyword.get(opts, :nat_interface, @default_nat_interface)
    client_subnet = Keyword.get(opts, :client_subnet, @default_entry_transit_subnet)

    entry_port = Keyword.get(opts, :entry_transit_port, @default_entry_transit_port)

    entry_attrs = %{
      id: Keyword.get(opts, :entry_transit_id, @default_entry_transit_id),
      node_id: entry_node.id,
      name: Keyword.get(opts, :entry_transit_name, @default_entry_transit_name),
      protocol: :awg,
      listen_port: entry_port,
      subnet: Keyword.get(opts, :entry_transit_subnet, @default_entry_transit_subnet),
      address: Keyword.get(opts, :entry_transit_address, @default_entry_transit_address),
      table: "off",
      post_up: routing_post_up(client_subnet, entry_port),
      pre_down: routing_pre_down(client_subnet, entry_port),
      target_state: :configured
    }

    exit_attrs = %{
      id: Keyword.get(opts, :exit_id, @default_exit_id),
      node_id: exit_node.id,
      name: Keyword.get(opts, :exit_name, @default_exit_name),
      protocol: :awg,
      listen_port: Keyword.get(opts, :exit_port, @default_exit_port),
      subnet: Keyword.get(opts, :exit_subnet, @default_exit_subnet),
      address: Keyword.get(opts, :exit_address, @default_exit_address),
      post_up: nat_post_up(nat_interface),
      post_down: nat_post_down(nat_interface),
      target_state: :configured
    }

    %{entry_transit: entry_attrs, exit: exit_attrs}
  end

  @doc """
  Возвращает атрибуты пиров, связывающих созданные инстансы каскада.

  `entry_wg` — WG-инстанс на entry-узле, к которому подключается ноутбук.
  Его подсеть используется для формирования конкретных `AllowedIPs` на
  exit-сервере.
  """
  @spec peer_attrs(Instance.t(), Instance.t(), Instance.t(), Node.t()) :: peer_plan()
  def peer_attrs(
        %Instance{} = entry_wg,
        %Instance{} = entry_transit,
        %Instance{} = exit_instance,
        %Node{} = exit_node
      ) do
    entry_peer = %{
      id: "#{entry_transit.id}-peer-#{exit_instance.id}",
      instance_id: entry_transit.id,
      name: "exit",
      public_key: exit_instance.public_key,
      allowed_ips: "0.0.0.0/0",
      endpoint: "#{exit_node.address}:#{exit_instance.listen_port}",
      persistent_keepalive: 25
    }

    exit_peer = %{
      id: "#{exit_instance.id}-peer-#{entry_transit.id}",
      instance_id: exit_instance.id,
      name: "entry-transit",
      public_key: entry_transit.public_key,
      allowed_ips: "#{entry_wg.subnet},#{source_ip(entry_transit.address)}/32"
    }

    %{entry_peer: entry_peer, exit_peer: exit_peer}
  end

  defp source_ip(address) when is_binary(address) do
    address |> String.split("/") |> List.first()
  end

  defp routing_post_up(client_subnet, table) do
    [
      "ip rule add from #{client_subnet} lookup #{table}",
      "ip route add default dev %i table #{table}"
    ]
  end

  defp routing_pre_down(client_subnet, table) do
    [
      "ip rule del from #{client_subnet} lookup #{table}",
      "ip route del default dev %i table #{table}"
    ]
  end

  defp nat_post_up(interface) do
    [
      "iptables -t nat -A POSTROUTING -o #{interface} -j MASQUERADE",
      "sysctl -w net.ipv4.ip_forward=1"
    ]
  end

  defp nat_post_down(interface) do
    ["iptables -t nat -D POSTROUTING -o #{interface} -j MASQUERADE"]
  end
end
