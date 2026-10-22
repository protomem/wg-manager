defmodule WGM.Agent.KeyStore do
  @moduledoc """
  Behaviour-шов хранилища приватных ключей серверных инстансов на узле.

  Реальная реализация пишет в файловую систему (`/etc/wireguard/wgm/...`
  или `/etc/amnezia/amneziawg/wgm/...`), фейк — в память для тестов.
  """

  @type protocol :: WGM.CLI.Adapter.protocol()

  @doc """
  Возвращает путь к файлу приватного ключа для инстанса.
  """
  @callback server_private_key_path(protocol(), instance_id :: String.t()) :: String.t()

  @doc """
  Читает сохранённый приватный ключ инстанса.
  """
  @callback read_private_key(protocol(), instance_id :: String.t()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @doc """
  Сохраняет приватный ключ инстанса на узле.

  Файл должен создаваться с правами `0600`, а содержащий его каталог —
  с правами `0700`.
  """
  @callback write_private_key(protocol(), instance_id :: String.t(), key :: String.t()) ::
              :ok | {:error, String.t()}
end
