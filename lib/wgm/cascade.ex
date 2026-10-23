defmodule WGM.Cascade do
  @moduledoc """
  Каскад: входной инстанс (принимает клиентов) → выходной инстанс (трафик в интернет).
  """

  @type t :: %__MODULE__{
          id: String.t(),
          entry_instance_id: String.t(),
          entry_transit_instance_id: String.t() | nil,
          exit_instance_id: String.t(),
          name: String.t() | nil,
          target: String.t() | nil
        }

  defstruct [
    :id,
    :entry_instance_id,
    :entry_transit_instance_id,
    :exit_instance_id,
    :name,
    :target
  ]
end
