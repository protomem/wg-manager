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

  @doc """
  Применяет конфиг к инстансу через `wg/awg syncconf`.
  """
  @callback syncconf(protocol(), interface :: String.t(), config_path :: String.t()) ::
              :ok | {:error, String.t()}

  @doc """
  Возвращает конфиг, очищенный от wg-quick-ключей (эквивалент `wg-quick strip`).
  """
  @callback strip_config(protocol(), interface :: String.t(), config_path :: String.t()) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc """
  Поднимает интерфейс через `wg-quick/awg-quick up <config_path>`.
  """
  @callback up(protocol(), interface :: String.t(), config_path :: String.t()) ::
              :ok | {:error, String.t()}

  @doc """
  Опускает интерфейс через `wg-quick/awg-quick down <config_path>`.
  """
  @callback down(protocol(), interface :: String.t(), config_path :: String.t()) ::
              :ok | {:error, String.t()}
end
