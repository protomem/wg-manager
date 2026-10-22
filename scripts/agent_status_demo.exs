alias WGM.{Agent, Instance, Node}

# Демо: read-only статус узла через агента (заглушка CLI).
WGM.CLI.FakeAdapter.start()

node = %Node{
  id: "demo-node",
  name: "entry",
  address: "193.233.91.130",
  role: :entry
}

instances = [
  %Instance{
    id: "demo-wg",
    node_id: "demo-node",
    name: "wg1",
    protocol: :wg,
    listen_port: 51_820,
    subnet: "10.0.0.0/24",
    private_key: "demo-private",
    public_key: "demo-public",
    address: "10.0.0.1/24"
  },
  %Instance{
    id: "demo-awg",
    node_id: "demo-node",
    name: "awg1",
    protocol: :awg,
    listen_port: 51_821,
    subnet: "10.1.0.0/24",
    private_key: "demo-private",
    public_key: "demo-public",
    address: "10.1.0.1/24"
  }
]

wg_dump =
  "demo-private\tdemo-public\t51820\toff\n" <>
    "peer-a\t\t192.168.1.2:1234\t10.0.0.2/32\t1699013400\t1024\t2048\t25\n"

awg_dump =
  "demo-private\tdemo-public\t51821\t" <>
    "3\t40\t100\t1\t2\t3\t4\t5\t6\t7\t8\t" <>
    "1\t2\t3\t4\t5\thpk\toff\n" <>
    "peer-b\t\t192.168.1.3:1234\t10.1.0.2/32\t1699013400\t4096\t8192\t0-0\n"

WGM.CLI.FakeAdapter.set_dump(:wg, "wg1", wg_dump)
WGM.CLI.FakeAdapter.set_dump(:awg, "awg1", awg_dump)
WGM.CLI.FakeAdapter.set_interface_state("wg1", :up)
WGM.CLI.FakeAdapter.set_interface_state("awg1", :down)

{:ok, agent} = Agent.start_link(node: node, instances: instances, adapter: WGM.CLI.FakeAdapter)

status = Agent.status(agent)

IO.puts("Node ID: #{status.node_id}")
IO.puts("Timestamp: #{DateTime.to_iso8601(status.timestamp)}")
IO.puts("")

for inst <- status.instances do
  IO.puts("Instance: #{inst.name} (#{inst.protocol})")
  IO.puts("  interface state: #{inst.interface_state}")
  IO.puts("  present: #{inst.present}")
  IO.puts("  peers: #{length(inst.peers || [])}")
  IO.puts("  error: #{inst.error || "none"}")
  IO.puts("")
end
