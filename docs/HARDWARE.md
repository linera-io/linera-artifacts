# Hardware requirements

What you need to run a Linera validator that keeps up with the network
under real load. These numbers come from operating the reference
validators against `linera.market` traffic — they are not theoretical
floors, they are what works in production.

## TL;DR

The reference validators each run on **two machines of 8 vCPUs / 64 GB
RAM**: one dedicated entirely to ScyllaDB, one running the Linera
workloads (shards + proxy).

| Deployment                | Machines                    | Disk (ScyllaDB data)   | Notes                                            |
|---------------------------|-----------------------------|------------------------|--------------------------------------------------|
| Kubernetes (reference)    | 2 × (8 vCPUs / 64 GB)       | 1 TB fast SSD          | What we run in production. Scylla gets its own node. |
| Single-host Docker Compose| 1 × (16 cores / 128 GB)     | 1 TB fast SSD          | The sum of the two reference machines on one box. |

**ScyllaDB is the bottleneck, and it sets the floor: never plan a
validator around giving ScyllaDB less than a full 8 vCPUs / 64 GB
machine's worth of resources.** On Kubernetes that means a dedicated
node; on a single Docker host it means a box big enough that Scylla's
share is 7-8 cores and ~51 GiB *after* everything else.

Network: 1 Gbps symmetric, public IPv4, ports 80 + 443 reachable for
Let's Encrypt and the validator endpoint (`19100` by default, fronted by
Caddy on 443).

## Disk requirements — performance, not medium

ScyllaDB's throughput is bounded by storage I/O. The requirement is a
**performance floor**, not a specific technology:

| Dimension        | Requirement       | Notes                                              |
|------------------|-------------------|----------------------------------------------------|
| Capacity         | 1 TB              | The reference validators are under 50 % used today; the headroom absorbs chain growth and compaction. |
| Write IOPS       | **≥ 15,000**      | Writes dominate (commitlog + memtable flush + compaction). |
| Read IOPS        | ≥ 5,000           | Reads are mostly absorbed by Scylla's cache and the validator's in-process caches. |
| Throughput       | **≥ 400 MB/s**    | Compaction is sequential-heavy.                    |
| Latency          | low single-digit ms | This is what disqualifies cheap network storage.  |

What meets it:

- **Local NVMe** — exceeds every number above by an order of magnitude.
  The safest choice on bare metal.
- **Provisioned cloud SSD** — acceptable *if provisioned to the floor*.
  The reference validators run GCP `pd-ssd` at 1 TB (≈30,000 IOPS,
  ≈480 MB/s). On AWS, `gp3` must be explicitly provisioned above its
  3,000 IOPS / 125 MB/s baseline; on OVH, use the high-speed class.

What does not:

- HDDs of any kind (including RAID arrays of them)
- Unprovisioned / burst-class network storage (small `gp2` volumes,
  default virtualized disks, Ceph on spinning rust)

We learned this the hard way on an OVH VM backed by slow network
storage. When the disk can't keep up, ScyllaDB compaction backpressures,
`linera-server` shards accumulate state in memory waiting on storage
acks, hit their cgroup memory limit, and get OOM-killed. Restart,
repeat:

| Metric                    | Slow network disk | Local NVMe (bare metal) |
|---------------------------|-------------------|-------------------------|
| OOM kills / 24h           | ~4                | **0**                   |
| Container restarts / 48h  | 5+                | **0**                   |
| Load average              | 20-24 (16 cores)  | **3-5**                 |

This is *not* solvable by raising memory limits. The root cause is I/O,
not RAM.

Filesystem on the data directory: ext4 or XFS. XFS is mildly preferred
by ScyllaDB for very large datasets but ext4 is fine for testnet
workloads.

## The reference topology (Kubernetes)

Per validator, two 8 vCPU / 64 GB machines:

- **ScyllaDB node** — dedicated (tainted `NoSchedule`), nothing else
  runs there. The `ScyllaCluster` pod requests **7 CPUs / 51 GiB** with
  Guaranteed QoS (the remaining core and memory go to the OS, kubelet
  and the Scylla manager agent), and the kubelet's static CPU manager
  pins Scylla's cores exclusively. See the `linera-validator-stack`
  chart and `HELM.md` for the three pieces that make this work
  (dedicated node pool, `cpuManagerPolicy: static`, perftune
  NodeConfig).
- **Workload node** — runs the shards and the proxy with the default
  chart resources (shards ≈ 8-12 GiB each, proxy ≈ 4-6 GiB).

## Single host (Docker Compose): why 16 cores / 128 GB

The compose stack runs everything the two reference machines run — on
one kernel:

- ScyllaDB (the dominant resource consumer)
- 4 `linera-server` shards
- `linera-proxy`
- Caddy
- Watchtower + cAdvisor + (optionally) a monitoring stack

To give ScyllaDB its full reference share (7 cores / 51 GiB) *and* run
the shards, you need the sum of the two reference machines:
**16 cores / 128 GB**. Suggested cgroup limits on that box:

| Service     | CPU limit  | Memory limit               | Reference equivalent               |
|-------------|------------|----------------------------|------------------------------------|
| ScyllaDB    | 7          | 51 GiB                     | 7c / 51 GiB pod on a dedicated node |
| Shards × 4  | 2 each     | 12 GiB each (48 GiB total) | shards on the workload node        |
| Proxy       | 1.5        | 6 GiB                      | proxy on the workload node         |
| Caddy (web) | 1          | 3 GiB                      | —                                  |
| Alloy       | 0.5        | 1 GiB                      | —                                  |
| cAdvisor    | 0.5        | 256 MiB                    | —                                  |
| Watchtower  | 0.25       | 256 MiB                    | —                                  |

Set `LIMIT_CPUS_SCYLLA=7` and `LIMIT_MEM_SCYLLA=51G` in `.env` to get
this — the shipped defaults are conservative and **must** be raised to
these values on a properly sized host.

Two things to know about this table:

- **Memory must add up; CPU may oversubscribe.** The memory column
  totals ≈110 GiB, leaving ≈18 GiB for the kernel, Docker, and — most
  importantly — the page cache. Never let memory limits exceed physical
  RAM. The CPU column intentionally sums past 16: CPU limits are burst
  ceilings, not reservations — the shards idle well below one core each
  in steady state, while Scylla's 7 are effectively pinned via `--smp`.
- **A single host cannot replicate the reference isolation.** On GKE,
  Scylla shares its node with nothing; on one box it shares the kernel,
  page cache, NIC and disk queue with everything else. The extra RAM
  headroom is what compensates. If you can pin Scylla's cores
  (`SCYLLA_CPUSET`) on a dedicated box, do it — see
  [Docker Compose reference](DOCKER-COMPOSE.md).

Hosts smaller than this will not keep up with sustained production
traffic — ScyllaDB gets squeezed first and the OOM cycle described
above sets in. Size the box to the table; when allocating, ScyllaDB
first, always.

## Why ScyllaDB needs ≥ 1 GiB per shard

ScyllaDB is sharded: one shard per CPU core it sees, each shard pinned
to a specific core with its own slice of memory. The compose file pins
ScyllaDB to `LIMIT_CPUS_SCYLLA` cores via `--smp`. Memory is bounded by
the cgroup limit `LIMIT_MEM_SCYLLA` — ScyllaDB reads it directly and
reserves its own headroom for OS buffers and non-shard overhead, so
**you do not pass `--memory` explicitly**.

ScyllaDB refuses to start if per-shard memory drops below 1 GiB. After
Scylla's automatic reserve (~2 GiB with `--overprovisioned 1`), the
rule of thumb to size is:

```
(LIMIT_MEM_SCYLLA - ~2 GiB) / LIMIT_CPUS_SCYLLA  ≥  ~1.2 GiB
```

The recommended `7 cores / 51 GiB` leaves ≈7.0 GiB usable per Scylla
shard — the same as the reference validators.

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
- Netfilter conntrack max ≥ 1,048,576 (`net.netfilter.nf_conntrack_max`)
  — heavily suggested. A validator opens many short-lived gRPC/DNS
  connections; a low limit fills the conntrack table and the kernel
  drops packets (including DNS), surfacing as cross-chain failures.
  Set it persistently:
  `echo 'net.netfilter.nf_conntrack_max=1048576' | sudo tee /etc/sysctl.d/99-linera.conf && sudo sysctl --system`
  (`deploy-validator.sh` warns if it is too low.)

If you have a setup that works well (or doesn't), let us know on
Discord or open an issue on
[linera-io/linera-artifacts](https://github.com/linera-io/linera-artifacts/issues).
