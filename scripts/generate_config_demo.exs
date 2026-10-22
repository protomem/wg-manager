# iex-демо: собери клиентский и серверный конфиг из желаемого состояния.
#
# Запуск:
#   mix run scripts/generate_config_demo.exs

alias WGM.{Cascade, ConfigGenerator, Instance, Node, Peer}

node = %Node{
  id: "node-entry",
  name: "entry",
  address: "193.233.91.130",
  role: :entry
}

awg_params = %Instance.AWGParams{
  jc: 5,
  jmin: 50,
  jmax: 100,
  s1: 100,
  s2: 200,
  s3: 300,
  s4: 400,
  h1: "1-10",
  h2: "11-20",
  h3: "21-30",
  h4: "31-40",
  i1: 1,
  i2: 2,
  i3: 3,
  i4: 4,
  i5: 5,
  header_protection_key: "demo-header-protection-key"
}

wg_instance = %Instance{
  id: "inst-wg-entry",
  node_id: node.id,
  name: "wg-entry",
  protocol: :wg,
  listen_port: 51_820,
  subnet: "10.0.0.0/24",
  private_key: "server-private-key-wg",
  public_key: "server-public-key-wg",
  address: "10.0.0.1/24",
  dns: "1.1.1.1",
  mtu: 1420
}

awg_instance = %Instance{
  id: "inst-awg-exit",
  node_id: node.id,
  name: "awg-exit",
  protocol: :awg,
  listen_port: 51_821,
  subnet: "10.0.1.0/24",
  private_key: "server-private-key-awg",
  public_key: "server-public-key-awg",
  address: "10.0.1.1/24",
  awg_params: awg_params
}

wg_peer = %Peer{
  id: "peer-laptop",
  instance_id: wg_instance.id,
  name: "laptop",
  private_key: "peer-private-key",
  public_key: "peer-public-key",
  preshared_key: "peer-preshared-key",
  allowed_ips: "0.0.0.0/0",
  persistent_keepalive: 25,
  address: "10.0.0.2/24",
  dns: "1.1.1.1"
}

awg_peer = %Peer{
  id: "peer-cascade",
  instance_id: awg_instance.id,
  name: "cascade-peer",
  private_key: "peer-private-key-awg",
  public_key: "peer-public-key-awg",
  preshared_key: "peer-preshared-key-awg",
  allowed_ips: "0.0.0.0/0",
  persistent_keepalive: 25,
  address: "10.0.1.2/24",
  dns: "1.1.1.1"
}

_cascade = %Cascade{
  id: "cascade-main",
  entry_instance_id: wg_instance.id,
  exit_instance_id: awg_instance.id,
  name: "laptop → entry → exit"
}

print_config = fn label, {:ok, config} ->
  IO.puts("=== #{label} ===")
  IO.puts(config)
end

print_config.(
  "WG серверный конфиг",
  ConfigGenerator.generate_server_config(wg_instance, [wg_peer])
)

print_config.(
  "WG клиентский конфиг",
  ConfigGenerator.generate_client_config(wg_instance, wg_peer, "#{node.address}:51820")
)

print_config.(
  "AWG серверный конфиг",
  ConfigGenerator.generate_server_config(awg_instance, [awg_peer])
)

print_config.(
  "AWG клиентский конфиг",
  ConfigGenerator.generate_client_config(awg_instance, awg_peer, "#{node.address}:51821")
)
