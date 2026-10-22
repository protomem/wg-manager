defmodule WGM.Agent.Observer do
  @moduledoc """
  Read-only наблюдение за состоянием узла через CLI-адаптер.
  """

  alias WGM.{Agent.Status, Parser}

  @doc """
  Формирует статус узла для заданного списка инстансов.
  """
  @spec observe(WGM.Node.t(), [WGM.Instance.t()], module()) :: Status.t()
  def observe(node, instances, adapter) do
    now = DateTime.utc_now()

    instance_statuses =
      Enum.map(instances, fn instance ->
        observe_instance(instance, adapter)
      end)

    %Status{
      node_id: node.id,
      timestamp: now,
      instances: instance_statuses
    }
  end

  defp observe_instance(instance, adapter) do
    interface = instance.name
    state_result = adapter.interface_state(interface)
    dump_result = adapter.show_dump(instance.protocol, interface)

    parsed = parse_dump_result(dump_result, instance.protocol)

    present = match?({:ok, _}, parsed)
    interface_state = interface_state_or_unknown(state_result)
    error = build_error(state_result, dump_result, parsed)

    {device, peers} =
      case parsed do
        {:ok, status} -> {scrub_device(status), status.peers}
        _ -> {nil, nil}
      end

    %Status.InstanceStatus{
      instance_id: instance.id,
      name: instance.name,
      protocol: instance.protocol,
      interface_state: interface_state,
      present: present,
      device: device,
      peers: peers,
      error: error
    }
  end

  defp parse_dump_result({:ok, dump}, protocol), do: Parser.parse_dump(dump, protocol)
  defp parse_dump_result({:error, _}, _protocol), do: {:error, :no_dump}

  defp build_error(_state, _dump, {:error, reason}) when is_binary(reason), do: reason

  defp build_error({:error, reason}, {:error, dump_reason}, _parsed),
    do: "#{reason}; #{dump_reason}"

  defp build_error({:error, reason}, _dump, _parsed), do: reason
  defp build_error(_state, {:error, reason}, _parsed), do: reason
  defp build_error(_state, _dump, _parsed), do: nil

  defp interface_state_or_unknown({:ok, state}), do: state
  defp interface_state_or_unknown({:error, _}), do: :unknown

  # Статус, отправляемый с узла, не должен содержать приватных ключей
  # живых интерфейсов (см. ADR «Секреты» и историю 32).
  defp scrub_device(status) do
    status
    |> Map.drop([:peers])
    |> Map.put(:private_key, nil)
  end
end
