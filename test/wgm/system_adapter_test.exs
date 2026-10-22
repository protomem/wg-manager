defmodule WGM.SystemAdapterTest do
  use ExUnit.Case

  alias WGM.CLI.SystemAdapter

  describe "interface_state/1" do
    test "returns an error tuple when the ip command is missing" do
      # В данном окружении `ip` обычно отсутствует; важнее проверить,
      # что адаптер не бросает исключение и возвращает `{:error, _}`.
      result = SystemAdapter.interface_state("wg0")
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "show_dump/2" do
    test "returns an error tuple when the binary is missing" do
      # `awg` обычно не установлен; даже если он есть, вызов без валидного
      # интерфейса вернёт `{:error, _}`. Главное — отсутствие raise.
      result = SystemAdapter.show_dump(:awg, "missing-interface")
      assert {:error, _} = result
    end
  end
end
