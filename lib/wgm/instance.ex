defmodule WGM.Instance do
  @moduledoc """
  VPN-инстанс на узле. Протокол (:wg или :awg) — атрибут инстанса.
  """

  alias WGM.Instance.AWGParams

  @type protocol :: :wg | :awg
  @type target_state :: :configured | :up | :down

  @type t :: %__MODULE__{
          id: String.t(),
          node_id: String.t(),
          name: String.t(),
          protocol: protocol(),
          listen_port: pos_integer(),
          subnet: String.t(),
          private_key: String.t() | nil,
          public_key: String.t(),
          address: String.t(),
          dns: String.t() | nil,
          mtu: pos_integer() | nil,
          awg_params: AWGParams.t() | nil,
          target_state: target_state()
        }

  defstruct [
    :id,
    :node_id,
    :name,
    :protocol,
    :listen_port,
    :subnet,
    :private_key,
    :public_key,
    :address,
    :dns,
    :mtu,
    :awg_params,
    :target_state
  ]

  defmodule AWGParams do
    @moduledoc """
    Параметры маскировки AmneziaWG. Параметры S1–S4, H1–H4 и HeaderProtectionKey
    должны совпадать на обеих сторонах; Jc/Jmin/Jmax и I1–I5 — клиентские.
    """

    @type t :: %__MODULE__{
            jc: non_neg_integer(),
            jmin: non_neg_integer(),
            jmax: non_neg_integer(),
            s1: non_neg_integer(),
            s2: non_neg_integer(),
            s3: non_neg_integer(),
            s4: non_neg_integer(),
            h1: String.t(),
            h2: String.t(),
            h3: String.t(),
            h4: String.t(),
            i1: non_neg_integer() | nil,
            i2: non_neg_integer() | nil,
            i3: non_neg_integer() | nil,
            i4: non_neg_integer() | nil,
            i5: non_neg_integer() | nil,
            header_protection_key: String.t() | nil
          }

    defstruct [
      :jc,
      :jmin,
      :jmax,
      :s1,
      :s2,
      :s3,
      :s4,
      :h1,
      :h2,
      :h3,
      :h4,
      :i1,
      :i2,
      :i3,
      :i4,
      :i5,
      :header_protection_key
    ]
  end
end
