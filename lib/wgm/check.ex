defmodule WGM.Check do
  @moduledoc """
  Модель результатов проверок (passive + active) и вывод пассивных проверок
  из статуса агента.
  """

  alias WGM.Agent.Status

  defmodule Result do
    @moduledoc """
    Результат одной проверки: узел, инстанс, возможно пир, вид проверки,
    статус, детальное сообщение и время.
    """

    @type status :: :ok | :error | :unknown

    @type t :: %__MODULE__{
            node_id: String.t(),
            instance_id: String.t() | nil,
            peer_id: String.t() | nil,
            kind: atom(),
            status: status(),
            detail: String.t() | nil,
            checked_at: DateTime.t(),
            last_success_at: DateTime.t() | nil
          }

    defstruct [
      :node_id,
      :instance_id,
      :peer_id,
      :kind,
      :status,
      :detail,
      :checked_at,
      :last_success_at
    ]
  end

  @doc """
  Преобразует агентский статус узла в список пассивных проверок:

    - `:interface_state` — по одной на инстанс;
    - `:handshake` — по одной на каждого пира инстанса;
    - `:transfer` — по одной на каждого пира инстанса.
  """
  @spec from_agent_status(Status.t()) :: [Result.t()]
  def from_agent_status(%Status{} = status) do
    Enum.flat_map(status.instances, fn instance ->
      instance_checks(status.node_id, instance, status.timestamp)
    end)
  end

  defp instance_checks(node_id, instance, checked_at) do
    interface = interface_check(node_id, instance, checked_at)
    peer_checks = peer_checks(node_id, instance, checked_at)
    [interface | peer_checks]
  end

  defp interface_check(node_id, instance, checked_at) do
    {check_status, detail} = interface_state_detail(instance)

    %Result{
      node_id: node_id,
      instance_id: instance.instance_id,
      peer_id: nil,
      kind: :interface_state,
      status: check_status,
      detail: detail,
      checked_at: checked_at,
      last_success_at: if(check_status == :ok, do: checked_at, else: nil)
    }
  end

  defp interface_state_detail(%{interface_state: :up} = instance),
    do: {:ok, "interface #{instance.name} is up"}

  defp interface_state_detail(%{interface_state: :down} = instance),
    do: {:error, "interface #{instance.name} is down"}

  defp interface_state_detail(%{interface_state: :unknown, error: nil} = instance),
    do: {:unknown, "interface #{instance.name} state is unknown"}

  defp interface_state_detail(%{interface_state: :unknown, error: error}),
    do: {:unknown, error}

  defp interface_state_detail(instance),
    do: {:unknown, "interface #{instance.name} state is unknown"}

  defp peer_checks(_node_id, %{peers: nil}, _checked_at), do: []

  defp peer_checks(node_id, instance, checked_at) do
    Enum.flat_map(instance.peers, fn peer ->
      [
        handshake_check(node_id, instance.instance_id, peer, checked_at),
        transfer_check(node_id, instance.instance_id, peer, checked_at)
      ]
    end)
  end

  defp handshake_check(node_id, instance_id, peer, checked_at) do
    if peer.latest_handshake > 0 do
      %Result{
        node_id: node_id,
        instance_id: instance_id,
        peer_id: peer.public_key,
        kind: :handshake,
        status: :ok,
        detail: "last handshake at #{peer.latest_handshake}",
        checked_at: checked_at,
        last_success_at: checked_at
      }
    else
      %Result{
        node_id: node_id,
        instance_id: instance_id,
        peer_id: peer.public_key,
        kind: :handshake,
        status: :error,
        detail: "no handshake received from #{peer.public_key}",
        checked_at: checked_at,
        last_success_at: nil
      }
    end
  end

  defp transfer_check(node_id, instance_id, peer, checked_at) do
    if peer.transfer_rx > 0 or peer.transfer_tx > 0 do
      %Result{
        node_id: node_id,
        instance_id: instance_id,
        peer_id: peer.public_key,
        kind: :transfer,
        status: :ok,
        detail: "rx=#{peer.transfer_rx} tx=#{peer.transfer_tx}",
        checked_at: checked_at,
        last_success_at: checked_at
      }
    else
      %Result{
        node_id: node_id,
        instance_id: instance_id,
        peer_id: peer.public_key,
        kind: :transfer,
        status: :error,
        detail: "no traffic for #{peer.public_key}",
        checked_at: checked_at,
        last_success_at: nil
      }
    end
  end
end
