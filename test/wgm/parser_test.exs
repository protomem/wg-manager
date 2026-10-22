defmodule WGM.ParserTest do
  use ExUnit.Case

  alias WGM.Parser

  describe "parse_wg_show_dump/1" do
    test "parses wg show dump with one peer" do
      dump = ~s"""
      server-private-key\tserver-public-key\t51820\toff
      peer-public-key\tpeer-preshared-key\t192.168.1.2:12345\t10.0.0.2/32\t1697967600\t1024\t2048\t25
      """

      assert {:ok, status} = Parser.parse_wg_show_dump(dump)

      assert status.private_key == "server-private-key"
      assert status.public_key == "server-public-key"
      assert status.listen_port == 51820
      assert status.fwmark == "off"
      assert length(status.peers) == 1

      [peer] = status.peers
      assert peer.public_key == "peer-public-key"
      assert peer.preshared_key == "peer-preshared-key"
      assert peer.endpoint == "192.168.1.2:12345"
      assert peer.allowed_ips == "10.0.0.2/32"
      assert peer.latest_handshake == 1_697_967_600
      assert peer.transfer_rx == 1024
      assert peer.transfer_tx == 2048
      assert peer.persistent_keepalive == 25
    end

    test "parses wg show dump with multiple peers" do
      dump = ~s"""
      server-private-key\tserver-public-key\t51820\t0
      peer1-public-key\t(none)\t(endpoint not set)\t10.0.0.2/32\t0\t0\t0\t0
      peer2-public-key\t(none)\t192.168.1.3:54321\t10.0.0.3/32\t1697967601\t2048\t4096\t0
      """

      assert {:ok, status} = Parser.parse_wg_show_dump(dump)
      assert length(status.peers) == 2
      assert Enum.at(status.peers, 0).public_key == "peer1-public-key"
      assert Enum.at(status.peers, 1).public_key == "peer2-public-key"
    end

    test "returns error on malformed device line" do
      assert {:error, _msg} = Parser.parse_wg_show_dump("too\tfew\tcolumns")
    end
  end

  describe "parse_awg_show_dump/1" do
    test "parses awg show dump with one peer" do
      dump = ~s"""
      server-private-key\tserver-public-key\t51821\t5\t50\t100\t100\t200\t300\t400\t1-10\t11-20\t21-30\t31-40\t1\t2\t3\t4\t5\thpk\toff
      peer-public-key\tpeer-preshared-key\t192.168.1.2:12345\t10.0.1.2/32\t1697967600\t1024\t2048\t25-35
      """

      assert {:ok, status} = Parser.parse_awg_show_dump(dump)

      assert status.private_key == "server-private-key"
      assert status.public_key == "server-public-key"
      assert status.listen_port == 51821
      assert status.fwmark == "off"

      awg = status.awg_params
      assert awg.jc == 5
      assert awg.jmin == 50
      assert awg.jmax == 100
      assert awg.s1 == 100
      assert awg.s2 == 200
      assert awg.s3 == 300
      assert awg.s4 == 400
      assert awg.h1 == "1-10"
      assert awg.h2 == "11-20"
      assert awg.h3 == "21-30"
      assert awg.h4 == "31-40"
      assert awg.i1 == 1
      assert awg.i2 == 2
      assert awg.i3 == 3
      assert awg.i4 == 4
      assert awg.i5 == 5
      assert awg.header_protection_key == "hpk"

      assert length(status.peers) == 1
      [peer] = status.peers
      assert peer.public_key == "peer-public-key"
      assert peer.persistent_keepalive == "25-35"
    end

    test "parses awg show dump with disabled masking" do
      dump = ~s"""
      server-private-key\tserver-public-key\t51821\t0\t0\t0\t0\t0\t0\t0\t1\t2\t3\t4\t0\t0\t0\t0\t0\t(none)\toff
      peer-public-key\t(none)\t(endpoint not set)\t10.0.1.2/32\t0\t0\t0\toff
      """

      assert {:ok, status} = Parser.parse_awg_show_dump(dump)
      assert status.awg_params.jc == 0
      assert status.awg_params.h1 == "1"
      assert status.peers |> hd() |> Map.get(:persistent_keepalive) == "off"
    end

    test "returns error on malformed awg device line" do
      assert {:error, _msg} = Parser.parse_awg_show_dump("too\tfew\tcolumns")
    end

    test "parses awg device line with extra unknown columns" do
      dump = ~s"""
      server-private-key\tserver-public-key\t51821\t5\t50\t100\t100\t200\t300\t400\t1-10\t11-20\t21-30\t31-40\t1\t2\t3\t4\t5\thpk\textra1\textra2\textra3\toff
      peer-public-key\tpeer-preshared-key\t192.168.1.2:12345\t10.0.1.2/32\t1697967600\t1024\t2048\t25-35
      """

      assert {:ok, status} = Parser.parse_awg_show_dump(dump)

      assert status.fwmark == "off"
      assert status.awg_params.jc == 5
      assert status.awg_params.s4 == 400
      assert status.awg_params.i5 == 5
      assert status.awg_params.header_protection_key == "hpk"
    end

    test "returns error on malformed peer line" do
      dump = ~s"""
      server-private-key\tserver-public-key\t51820\toff
      peer-public-key\twrong-columns
      """

      assert {:error, _msg} = Parser.parse_wg_show_dump(dump)
    end
  end
end
