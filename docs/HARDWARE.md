# Hardware requirements

What you need to run a Linera validator that keeps up with the network
under real load. These numbers come from operating the reference
validators against `linera.market` traffic — they are not theoretical
floors, they are what works in production.

## TL;DR

| Tier        | CPU        | RAM   | Disk                      | Notes                                            |
|-------------|-----------|-------|---------------------------|--------------------------------------------------|
| Minimum     | 8 cores   | 32 GB | NVMe SSD, 500 GB+         | Will run; expect tight headroom under spikes.    |
| Recommended | 16 cores  | 64 GB | NVMe SSD, 1 TB+           | Default tuning targets this. No babysitting.     |
| Production  | 32+ cores | 128+ GB | NVMe SSD, 2 TB+         | Future-proof; raise `LIMIT_*_SCYLLA` accordingly.|

Network: 1 Gbps symmetric, public IPv4, ports 80 + 443 reachable for
Let's Encrypt and the validator endpoint (`19100` by default, fronted by
Caddy on 443).

## Why local NVMe is non-negotiable

ScyllaDB's throughput is bounded by storage I/O latency. On slow disks
(HDDs, network-attached block storage, virtualized QEMU disks),
ScyllaDB compaction backpressures, which causes the upstream
`linera-server` shards to accumulate state in memory waiting on storage
acks. The shards then hit their cgroup memory limit and the kernel
OOM-kills them. Restart, repeat.

We observed this directly on an OVH VM backed by network storage:

| Metric              | Network-attached disk | Local NVMe (bare metal) |
|---------------------|----------------------|-------------------------|
| OOM kills / 24h     | ~4                   | **0**                   |
| Container restarts / 48h | 5+               | **0**                   |
| Load average        | 20-24 (16 cores)     | **3-5**                 |

This is *not* solvable by raising memory limits. The root cause is I/O
latency, not RAM exhaustion. Pick a host with **local NVMe SSDs**
(or equivalently low-latency local storage). Avoid:

- HDDs of any kind
- Network block storage (Ceph RBD, EBS gp2, OVH virtual disks, etc.)
- Spinning-rust RAID arrays

Local SATA SSD will work in a pinch but expect higher tail latencies
than NVMe.

## Why 16 cores / 64 GB is the recommended default

The compose stack runs:

- ScyllaDB (the dominant resource consumer)
- 4 `linera-server` shards
- `linera-proxy`
- Caddy
- Watchtower + cAdvisor + (optionally) a monitoring stack

Default cgroup allocations for the recommended tier:

| Service     | CPU       | Memory  |
|-------------|-----------|---------|
| ScyllaDB    | 4         | 30 GiB  |
| Shards × 4  | 2 each    | 6 GiB each (24 GiB total) |
| Proxy       | 1.5       | 4 GiB   |
| Caddy (web) | 1         | 3 GiB   |
| Alloy       | 0.5       | 1 GiB   |
| cAdvisor    | 0.5       | 256 MiB |
| Watchtower  | 0.25      | 256 MiB |
| **Total**   | **~14.75** | **~62 GiB** |

This leaves ~1 CPU and ~2 GiB for the host kernel and Docker daemon.

If your host is smaller, override `LIMIT_CPUS_*` and `LIMIT_MEM_*` in
`.env`. See [Docker Compose reference](DOCKER-COMPOSE.md#configuration-via-env)
for the full list.

## Why ScyllaDB needs ≥ 1 GiB per shard

ScyllaDB is sharded: one shard per CPU core it sees, each shard pinned
to a specific core with its own slice of memory. The compose file pins
ScyllaDB to `LIMIT_CPUS_SCYLLA` cores via `--smp`. Memory is bounded by
the cgroup limit `LIMIT_MEM_SCYLLA` — ScyllaDB reads it directly and
reserves its own headroom for OS buffers and non-shard overhead, so
**you do not pass `--memory` explicitly**.

ScyllaDB refuses to start if per-shard memory drops below 1 GiB. After
Scylla's automatic reserve (~2 GiB on a 30 GiB cgroup with
`--overprovisioned 1`), the rule of thumb to size is:

```
(LIMIT_MEM_SCYLLA - ~2 GiB) / LIMIT_CPUS_SCYLLA  ≥  ~1.2 GiB
```

Default `4 cores / 30 GiB` leaves ~7 GiB usable per shard — far above
the floor.

If you raise `LIMIT_CPUS_SCYLLA` to use more cores, raise
`LIMIT_MEM_SCYLLA` proportionally — that's the only knob you need to
touch. See
[ScyllaDB sizing](DOCKER-COMPOSE.md#scylladb-sizing--how---smp-and---memory-work)
for the full table and a worked example.

## Operating-system requirements

- Linux x86_64 (kernel 5.10+ recommended for ScyllaDB)
- Docker Engine 24+ with the compose v2 plugin
- `wget`, `jq`, `python3` (used by `deploy-validator.sh`)
- AIO max events ≥ 1,048,576 (`fs.aio-max-nr`) — the `scylla-setup`
  container handles this for you

Filesystem on the data directory: ext4 or XFS. XFS is mildly
preferred by ScyllaDB for very large datasets but ext4 is fine for
testnet workloads.

If you have a setup that works well (or doesn't), let us know on
Discord or open an issue on
[linera-io/linera-artifacts](https://github.com/linera-io/linera-artifacts/issues).
