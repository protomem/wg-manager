defmodule WGM.Keygen do
  @moduledoc """
  Генерация ключевых пар и pre-shared ключей через CLI-адаптер.
  """

  alias WGM.CLI.Adapter

  @type key_pair :: %{private_key: String.t(), public_key: String.t()}

  @doc """
  Генерирует новую ключевую пару для указанного протокола.
  """
  @spec generate_keypair(Adapter.protocol(), module()) :: {:ok, key_pair()} | {:error, String.t()}
  def generate_keypair(protocol, adapter \\ WGM.CLI.SystemAdapter) do
    with {:ok, private_key} <- adapter.genkey(protocol),
         {:ok, public_key} <- adapter.pubkey(private_key, protocol) do
      {:ok, %{private_key: private_key, public_key: public_key}}
    end
  end

  @doc """
  Генерирует pre-shared ключ.
  """
  @spec generate_psk(module()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_psk(adapter \\ WGM.CLI.SystemAdapter) do
    adapter.genpsk()
  end
end
