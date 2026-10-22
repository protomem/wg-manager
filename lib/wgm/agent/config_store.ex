defmodule WGM.Agent.ConfigStore do
  @moduledoc """
  Behaviour-шов хранилища конфигурационных файлов инстансов на узле.

  Серверные конфиги инстансов хранятся в:
    - `/etc/wireguard/<name>.conf` для WG;
    - `/etc/amnezia/amneziawg/<name>.conf` для AWG.

  Реализация отвечает за атомарную запись, ротацию бэкапов и удаление.
  """

  @type protocol :: WGM.CLI.Adapter.protocol()

  @doc """
  Возвращает путь к конфигурационному файлу инстанса.
  """
  @callback config_path(protocol(), instance_name :: String.t()) :: String.t()

  @doc """
  Читает текущий конфиг инстанса.
  """
  @callback read_config(protocol(), instance_name :: String.t()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Атомарно записывает конфиг инстанса (temp + rename).
  """
  @callback write_config(protocol(), instance_name :: String.t(), content :: String.t()) ::
              :ok | {:error, String.t()}

  @doc """
  Создаёт бэкап текущего конфига с ротацией (по умолчанию 5 копий).
  """
  @callback backup_config(protocol(), instance_name :: String.t()) ::
              :ok | {:error, String.t()}

  @doc """
  Удаляет конфиг инстанса.
  """
  @callback delete_config(protocol(), instance_name :: String.t()) ::
              :ok | {:error, String.t()}
end
