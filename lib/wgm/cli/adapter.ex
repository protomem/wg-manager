defmodule WGM.CLI.Adapter do
  @moduledoc """
  Behaviour-шов для вызовов внешних CLI-утилит `wg`/`awg`.
  """

  @type protocol :: :wg | :awg

  @callback genkey(protocol()) :: {:ok, String.t()} | {:error, String.t()}
  @callback pubkey(private_key :: String.t(), protocol()) ::
              {:ok, String.t()} | {:error, String.t()}
  @callback genpsk() :: {:ok, String.t()} | {:error, String.t()}
end
