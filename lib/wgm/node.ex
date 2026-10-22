defmodule WGM.Node do
  @moduledoc """
  VPN-узел: сервер, на котором работает агент и размещаются инстансы.
  """

  @type role :: :entry | :exit | :standalone

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          address: String.t(),
          role: role(),
          description: String.t() | nil
        }

  defstruct [:id, :name, :address, :role, :description]
end
