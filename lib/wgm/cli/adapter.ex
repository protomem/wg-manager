defmodule WGM.CLI.Adapter do
  @moduledoc """
  Behaviour-шов для вызовов внешних CLI-утилит `wg`/`awg`.
  """

  @type protocol :: :wg | :awg

  @callback genkey(protocol()) :: {:ok, String.t()} | {:error, String.t()}
  @callback pubkey(private_key :: String.t(), protocol()) ::
              {:ok, String.t()} | {:error, String.t()}
  @callback genpsk() :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Возвращает вывод `wg show dump <interface>` или `awg show dump <interface>`.
  """
  @callback show_dump(protocol(), interface :: String.t()) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc """
  Возвращает состояние сетевого интерфейса: `:up`, `:down` или `:unknown`.
  """
  @callback interface_state(interface :: String.t()) ::
              {:ok, :up | :down | :unknown} | {:error, String.t()}
end
