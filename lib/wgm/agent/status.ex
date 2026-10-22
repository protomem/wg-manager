defmodule WGM.Agent.Status do
  @moduledoc """
  Структурированный статус узла, полученный агентом в режиме read-only.
  """

  defmodule InstanceStatus do
    @moduledoc """
    Статус одного инстанса на узле.
    """

    @type t :: %__MODULE__{
            instance_id: String.t(),
            name: String.t(),
            protocol: WGM.Instance.protocol(),
            interface_state: :up | :down | :unknown,
            present: boolean(),
            device: WGM.Parser.scrubbed_status() | nil,
            peers: [WGM.Parser.peer_status()] | nil,
            error: String.t() | nil
          }

    defstruct [
      :instance_id,
      :name,
      :protocol,
      :interface_state,
      :present,
      :device,
      :peers,
      :error
    ]
  end

  @type t :: %__MODULE__{
          node_id: String.t(),
          timestamp: DateTime.t(),
          instances: [InstanceStatus.t()]
        }

  defstruct [:node_id, :timestamp, :instances]
end
