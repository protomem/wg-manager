defmodule WGM.Peer do
  @moduledoc """
  Пир инстанса: клиентское устройство или downstream-узел каскада.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          instance_id: String.t(),
          name: String.t(),
          private_key: String.t() | nil,
          public_key: String.t(),
          preshared_key: String.t() | nil,
          allowed_ips: String.t(),
          persistent_keepalive: String.t() | pos_integer() | nil,
          endpoint: String.t() | nil,
          address: String.t() | nil,
          dns: String.t() | nil
        }

  defstruct [
    :id,
    :instance_id,
    :name,
    :private_key,
    :public_key,
    :preshared_key,
    :allowed_ips,
    :persistent_keepalive,
    :endpoint,
    :address,
    :dns
  ]
end
