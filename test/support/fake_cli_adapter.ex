defmodule WGM.CLI.FakeAdapter do
  @moduledoc """
  Фейковый CLI-адаптер для тестов. Генерирует детерминированные "ключи" на
  основе счётчика вызовов.
  """

  @behaviour WGM.CLI.Adapter

  @impl true
  def genkey(_protocol) do
    {:ok, "private-key-#{next_counter()}"}
  end

  @impl true
  def pubkey(private_key, _protocol) do
    {:ok, "public-for-#{private_key}"}
  end

  @impl true
  def genpsk do
    {:ok, "psk-#{next_counter()}"}
  end

  defp next_counter do
    :ets.update_counter(__MODULE__, :counter, {2, 1}, {:counter, 0})
  end
end
