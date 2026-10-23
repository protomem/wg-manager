defmodule WGM.Cascade.Builder do
  @moduledoc """
  Генератор декларативного плана каскада вход→выход.

  На основе входного и выходного узла возвращает атрибуты инстансов
  (AWG-транзит на входном узле и AWG-приёмник на выходном) и пиров,
  которые связывают эти инстансы. Публичные ключи подставляются
  после создания инстансов — когда агенты узлов сгенерируют ключевые пары.
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
    - `:nat_interface` — интерфейс для NAT-masquerade (по умолчанию `eth0`).
  """
  @spec plan_instances(Node.t(), Node.t(), keyword()) :: instance_plan()
  def plan_instances(%Node{} = entry_node, %Node{} = exit_node, opts \\ []) do
    nat_interface = Keyword.get(opts, :nat_interface, @default_nat_interface)

    entry_attrs = %{
      id: Keyword.get(opts, :entry_transit_id, @default_entry_transit_id),
      node_id: entry_node.id,
      name: Keyword.get(opts, :entry_transit_name, @default_entry_transit_name),
      protocol: :awg,
      listen_port: Keyword.get(opts, :entry_transit_port, @default_entry_transit_port),
      subnet: Keyword.get(opts, :entry_transit_subnet, @default_entry_transit_subnet),
      address: Keyword.get(opts, :entry_transit_address, @default_entry_transit_address),
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
  """
  @spec peer_attrs(Instance.t(), Instance.t(), Node.t()) :: peer_plan()
  def peer_attrs(
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
      allowed_ips: entry_transit.subnet
    }

    %{entry_peer: entry_peer, exit_peer: exit_peer}
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
