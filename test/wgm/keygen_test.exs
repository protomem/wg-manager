defmodule WGM.KeygenTest do
  use ExUnit.Case

  alias WGM.Keygen

  setup do
    :ets.insert(WGM.CLI.FakeAdapter, {:counter, 0})
    :ok
  end

  describe "generate_keypair/2" do
    test "generates a key pair via adapter" do
      assert {:ok, %{private_key: private_key, public_key: public_key}} =
               Keygen.generate_keypair(:wg, WGM.CLI.FakeAdapter)

      assert private_key == "private-key-1"
      assert public_key == "public-for-private-key-1"
    end

    test "uses protocol-specific key material" do
      assert {:ok, %{private_key: private_key}} =
               Keygen.generate_keypair(:awg, WGM.CLI.FakeAdapter)

      assert private_key == "private-key-1"
    end
  end

  describe "generate_psk/1" do
    test "generates a pre-shared key via adapter" do
      assert {:ok, psk} = Keygen.generate_psk(WGM.CLI.FakeAdapter)
      assert psk == "psk-1"
    end
  end
end
