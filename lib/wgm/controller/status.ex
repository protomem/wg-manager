defmodule WGM.Controller.Status do
  @moduledoc """
  Агрегированный статус узла, полученный контроллером от агента.
  """

  @type t :: %__MODULE__{
          node_id: String.t(),
          node_name: String.t(),
          online: boolean(),
          last_contact: DateTime.t() | nil,
          agent_status: WGM.Agent.Status.t() | nil
        }

  defstruct [:node_id, :node_name, :online, :last_contact, :agent_status]
end
