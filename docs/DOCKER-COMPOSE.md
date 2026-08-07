# Docker Compose reference

The `docker/` stack runs a single Linera validator on one
machine, joining an existing network. This is the canonical path for
external validators on a VM or bare-metal host.

If you prefer Kubernetes, see [`HELM.md`](HELM.md).

## What you get

| Service        | Image                               | Role                                                                    |
|----------------|-------------------------------------|-------------------------------------------------------------------------|
| `web`          | `caddy:2.10.2-alpine`               | TLS terminator + gRPC reverse proxy. Obtains Let's Encrypt automatically. |
| `scylla-setup` | `ubuntu:24.04` (privileged)         | One-shot host sysctl tuning for ScyllaDB (aio-max-nr, TCP buffers, …).   |
| `scylla`       | `scylladb/scylla:6.2.3`             | Storage backend.                                                        |
| `shard-init`   | `linera` (from linera-public-registry) | One-shot: initialize the validator DB from `genesis.json`.           |
| `shard-{0..3}` | same                                | Validator shards (default: 4).                                          |
| `proxy`        | same                                | gRPC proxy behind Caddy.                                                |
| `watchtower`   | `nickfedor/watchtower:1.15.0`       | Label-driven auto-update of the Linera image.                           |

The shape mirrors the Helm chart so the same `server.json` + `genesis.json`
work in both worlds.

## One-command deploy

```bash
git clone https://github.com/linera-io/linera-artifacts.git
cd linera-artifacts
./scripts/deploy-validator.sh validator.example.com admin@example.com
```

`deploy-validator.sh` handles everything:

1. Downloads the current network `genesis.json` from
   `https://storage.googleapis.com/linera-io-dev-public/testnet-conway/genesis.json`
2. Generates a matching `validator-config.toml`
3. Runs the linera image to generate a fresh `server.json` (your
   signing key — private, treat like an SSH key)
4. Writes `.env` from `.env.production.template` **with your values filled
   in** — `DOMAIN`, `ACME_EMAIL`, `GENESIS_URL`, `GENESIS_BUCKET`,
   `GENESIS_PATH_PREFIX`, `VALIDATOR_KEY`, `VALIDATOR_NAME`, `HOSTNAME`,
   `LINERA_IMAGE`, `NUM_SHARDS`. Re-running is safe: an existing `.env` is
   backed up and only those keys are patched, so your tuning survives.
5. Starts the stack with `docker compose up -d --wait`

Options:

```text
--skip-genesis      Don't download — assume genesis.json is already there.
--force-genesis     Re-download even if a copy exists.
--image-tag TAG     Override the linera image tag (default: testnet_conway_release).
--linera-image REF  Override the full image reference.
--xfs-path PATH     Bind-mount this XFS dir for ScyllaDB data.
--num-shards N      Number of shards (must match docker-compose.yaml services).
--dry-run           Print what would happen, change nothing.
```

## Manual deploy

If you prefer to do each step yourself:

```bash
cd docker

# 1. Env file from template
cp .env.production.template .env
#    Edit DOMAIN and ACME_EMAIL. Everything else is optional and already
#    defaulted — see "Configuration via .env" below.

# 2. Genesis
wget -O genesis.json \
  https://storage.googleapis.com/linera-io-dev-public/testnet-conway/genesis.json

# 3. Validator config (see scripts/deploy-validator.sh for the format)
cat > validator-config.toml <<'EOF'
server_config_path = "server.json"
host = "validator.example.com"
port = 443

[external_protocol]
Grpc = "Tls"

[internal_protocol]
Grpc = "ClearText"

[[proxies]]
host = "proxy"
public_port = 443
private_port = 20100
metrics_port = 21100

[[shards]]
host = "docker-shard-1"
port = 19100
metrics_port = 21100

# …repeat for shards 2-4
EOF

# 4. Generate signing key
docker run --rm \
  -v "$PWD:/config" -w /config \
  us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera:testnet_conway_release \
  /linera-server generate --validators validator-config.toml

# 5. Bring it up
docker compose up -d --wait
```

## Configuration via .env

The canonical reference is
[`.env.production.template`](https://github.com/linera-io/linera-artifacts/blob/main/docker/.env.production.template).

**Required: `DOMAIN` and `ACME_EMAIL`.** That is the whole list. Every other
variable in the template — bar `HOSTNAME`, covered below — is commented out
and the value shown beside it is the default the stack already applies, so
uncomment a line only to change it. The other two things a validator needs
— `server.json` and `genesis.json` — are files, not variables: the `docker/`
directory is bind-mounted at `/config` and the containers read both from
there.

A few variables in the template are recorded by `deploy-validator.sh` but
read by no container: `GENESIS_URL`, `GENESIS_BUCKET`, `GENESIS_PATH_PREFIX`
(they tell the *script* where to fetch genesis from), and `VALIDATOR_KEY` /
`VALIDATOR_NAME` (informational — the key in use is `server.json`). Editing
them does not change what runs. `HOSTNAME` is used only by the observability
overlays, as a metrics/logs label.

Key variables:

| Variable              | Default                               | Notes                                                                                      |
|-----------------------|---------------------------------------|--------------------------------------------------------------------------------------------|
| `DOMAIN`              | `your-domain.example.com`             | Public hostname. Caddy obtains a Let's Encrypt cert for this.                              |
| `ACME_EMAIL`          | `admin@example.com`                   | Registered with Let's Encrypt.                                                             |
| `GENESIS_URL`         | `…/testnet-conway/genesis.json`       | Where `deploy-validator.sh` fetches genesis from. The stack itself reads `./genesis.json`. |
| `LINERA_IMAGE`        | `…/linera-public-registry/linera:testnet_conway_release` | Upstream image. Update to change network compatibility.                |
| `SCYLLA_DEVELOPER_MODE` | `0`                                 | Set to `1` only for local testing (skips ScyllaDB io_setup checks).                       |
| `STORAGE_REPLICATION_FACTOR` | `1`                            | Matches single-node Scylla. Do not change without a Scylla cluster.                         |
| `PROXY_PORT`          | `19100`                               | Host port the proxy is bound to (behind Caddy on 443).                                     |
| `LIMIT_CPUS_SHARD_N` / `LIMIT_MEM_SHARD_N` | per-shard                | Per-shard cgroup CPU / memory limits. Applied by `docker compose up` on Compose v2.        |
| `LINERA_EXECUTION_STATE_CACHE_SIZE` | `20000`                 | Matches the GKE validators. Lower on a small/low-RAM box to save RAM. Shard-only.          |
| `LINERA_BLOCK_CACHE_SIZE` | `20000`                           | Matches the GKE validators. Lower on a small/low-RAM box to save RAM. Shard-only.          |
| `WATCHTOWER_INTERVAL` | `30`                                  | Seconds between image-update checks.                                                       |
| `LIMIT_CPUS_SCYLLA`   | `4`                                   | CPU cgroup budget for ScyllaDB. Also drives `--smp` (shard count). See **ScyllaDB sizing** below. |
| `LIMIT_MEM_SCYLLA`    | `30G`                                 | Memory cgroup budget for the ScyllaDB container. ScyllaDB reads this and reserves its own headroom — see below. |
| `SCYLLA_SMP`          | `${LIMIT_CPUS_SCYLLA}`                | Override the shard count independently of the CPU limit. Rarely needed.                    |

## Cache tuning — matching GKE on a big enough box

The shards and proxy carry storage (LRU) and in-memory caches. The
single-host stack ships them **defaulted to the same values as the
testnet-conway GKE validators** (`helm/linera-validator/values.yaml`,
`shards.cli` / `proxies.cli`), so on a sufficiently large box you can
leave them untouched and get GKE-class cache behavior. On a small or
low-RAM box, lower them in `.env`.

All of these are applied to **both** shards and the proxy:

| Variable                                    | Default       | Unit     |
|---------------------------------------------|---------------|----------|
| `LINERA_STORAGE_MAX_CACHE_SIZE`             | `1000000000`  | bytes    |
| `LINERA_STORAGE_MAX_CACHE_ENTRIES`          | `500000`      | entries  |
| `LINERA_STORAGE_MAX_VALUE_ENTRY_SIZE`       | `1000000`     | bytes    |
| `LINERA_STORAGE_MAX_FIND_KEYS_ENTRY_SIZE`   | `1000000`     | bytes    |
| `LINERA_STORAGE_MAX_FIND_KEY_VALUES_ENTRY_SIZE` | `1000000` | bytes    |
| `LINERA_STORAGE_MAX_CACHE_VALUE_SIZE`       | `500000000`   | bytes    |
| `LINERA_STORAGE_MAX_CACHE_FIND_KEYS_SIZE`   | `200000000`   | bytes    |
| `LINERA_STORAGE_MAX_CACHE_FIND_KEY_VALUES_SIZE` | `10000000` | bytes   |
| `LINERA_BLOB_CACHE_SIZE`                    | `1000`        | entries  |
| `LINERA_CONFIRMED_BLOCK_CACHE_SIZE`         | `10000`       | entries  |
| `LINERA_CERTIFICATE_CACHE_SIZE`             | `5000`        | entries  |
| `LINERA_CERTIFICATE_RAW_CACHE_SIZE`         | `50000`       | entries  |
| `LINERA_EVENT_CACHE_SIZE`                   | `20000`       | entries  |

Shard-only (the proxy does not execute blocks, so these are not passed
to it):

| Variable                            | Default  | Unit     |
|-------------------------------------|----------|----------|
| `LINERA_EXECUTION_STATE_CACHE_SIZE` | `20000`  | entries  |
| `LINERA_BLOCK_CACHE_SIZE`           | `20000`  | entries  |
| `LINERA_CHAIN_WORKER_TTL_MS`        | `300000` | ms       |

Previous releases shipped `LINERA_BLOCK_CACHE_SIZE` and
`LINERA_EXECUTION_STATE_CACHE_SIZE` detuned (2500 / 5000) to fit a
low-RAM host, and gave the proxy **no** storage-cache flags at all. Both
are now at GKE parity by default. `upgrade-env.sh` appends the new
variables commented-out, so existing deployments keep their current
behavior until you opt in.

## ScyllaDB sizing — how `--smp` and `--memory` work

ScyllaDB is a sharded database: each shard is pinned to a single CPU and
gets a slice of the total memory budget. The compose file controls the
layout via:

* `--smp ${SCYLLA_SMP:-${LIMIT_CPUS_SCYLLA:-4}}` — the number of internal
  shards. Default 4, matching the CPU cgroup quota.
* `LIMIT_MEM_SCYLLA` — the cgroup memory limit on the container.
  Default 30 GiB. ScyllaDB reads this directly and reserves its own
  headroom for OS buffers, the network stack, and non-shard overhead
  (verified empirically: at a 1 GiB cgroup limit ScyllaDB allocates
  ~50% to itself in dev mode, ~7-10% in production mode with
  `--overprovisioned 1`). **Do not pass `--memory` explicitly** —
  doing so disables Scylla's automatic headroom and causes the
  container to crash with `not enough memory` or get OOM-killed.

Per-shard memory must be **≥ 1 GiB** or ScyllaDB refuses to start with
`Only N MiB per shard; this is below the recommended minimum of 1 GiB/shard;
terminating.` After Scylla's auto-reserve, the rule of thumb is:

```
(LIMIT_MEM_SCYLLA - ~2 GiB) / SCYLLA_SMP  ≥  ~1.2 GiB
```

Examples that work with the default `LIMIT_MEM_SCYLLA=30G`:

| `SCYLLA_SMP` | Per-shard usable | OK?                   |
|--------------|------------------|-----------------------|
| 4            | ~6 GiB           | ✅ default — plenty    |
| 8            | ~3 GiB           | ✅                     |
| 16           | ~1.5 GiB         | ✅                     |
| 22           | ~1.1 GiB         | ✅ tight               |
| 24           | ~1.0 GiB         | ❌ at the edge         |
| 32           | ~0.75 GiB        | ❌ fails to start      |

If you want ScyllaDB to use more cores, raise `LIMIT_MEM_SCYLLA`
proportionally — that's the only knob you need to touch. Example, to
run 16 ScyllaDB shards comfortably:

```
LIMIT_CPUS_SCYLLA=16
LIMIT_MEM_SCYLLA=24G
```

!!! warning "Reducing the shard count requires a data wipe"
    `--smp` can only be **increased** on existing data. ScyllaDB tablets
    don't support shrinking the shard count. If you need to reduce
    `LIMIT_CPUS_SCYLLA` after running the validator, wipe the
    `${SCYLLA_DATA_DIR:-./data/scylla}` volume and re-sync from genesis.

## Dedicated-hardware ScyllaDB tuning

By default the stack assumes ScyllaDB **shares** the host with the
shards, the proxy, and Caddy: it runs with `--overprovisioned 1` and no
CPU pinning. On a box where you can give ScyllaDB its own cores, three
opt-in knobs move it toward GKE-class isolation:

| Variable                | Default | Effect                                                                 |
|-------------------------|---------|------------------------------------------------------------------------|
| `SCYLLA_CPUSET`         | *(unset)* | Pins the ScyllaDB container to specific logical CPUs (Docker `cpuset`). E.g. `0-15`. |
| `WORKLOAD_CPUSET`       | *(unset)* | Pins everything else (shards, proxy, Caddy, Watchtower) to the complementary logical CPUs. |
| `SCYLLA_OVERPROVISIONED`| `1`     | Set to `0` on a dedicated box so ScyllaDB stops yielding CPU it assumes others need. |

Set the two cpusets **together**. `SCYLLA_CPUSET` alone confines
ScyllaDB but does not protect it: the kernel is still free to schedule
the shards onto ScyllaDB's cores. The `LIMIT_CPUS_*` variables can't
help here — those are cgroup *quotas* that cap how much CPU time a
service gets, not *which* cores it runs on. The `WORKLOAD_CPUSET`
fence is what makes the isolation two-sided. A cpuset is a hard
scheduler guarantee: a pinned container can never run outside its set.

On a 16-core / 32-thread host, for example:

```bash
SCYLLA_CPUSET=0-15        # ScyllaDB owns the first die — private L3
WORKLOAD_CPUSET=18-31     # everything else on the second die
SCYLLA_OVERPROVISIONED=0
LIMIT_CPUS_SCYLLA=16      # match the cpuset size (drives --smp)
LIMIT_MEM_SCYLLA=51G      # keep ≥ ~1.2 GiB per Scylla shard
```

CPUs 16–17 are deliberately left out of both sets: the OS, Docker, and
network interrupt handlers need somewhere to run that is not ScyllaDB's
cores. ScyllaDB's own tuning guidance reserves cores for network IRQs
the same way.

### Choosing which cores to pin

`cpuset` values are **logical CPU numbers**, and which numbers map to
which physical core differs between machines. Check `lscpu -e` before
picking ranges — there are two traps:

- **SMT siblings.** On a hyperthreaded machine, two logical CPUs share
  each physical core's execution units. If one sibling lands in
  `SCYLLA_CPUSET` and the other in `WORKLOAD_CPUSET`, a shard can still
  steal cycles from ScyllaDB through the shared core and the fence is
  cosmetic. Keep sibling pairs on the same side of the split.
- **Cache/die boundaries.** On chiplet CPUs (AMD Ryzen/EPYC CCDs), each
  die has its own L3 cache. Align the split to a die boundary and
  ScyllaDB gets a *private* L3 — the shards can't evict its working
  set. Cache isolation on top of CPU isolation, for free.

`lscpu -e` shows both. On a 16-core/32-thread AMD Ryzen (two 8-core
dies, SMT siblings adjacent — CPUs 0,1 = core 0, CPUs 2,3 = core 1, …):

```console
$ lscpu -e=CPU,CORE,L3
CPU CORE L3
  0    0  0    # CPUs 0-15  = cores 0-7  = die 0
  1    0  0
  2    1  0
...
 16    8  1    # CPUs 16-31 = cores 8-15 = die 1
 17    8  1
...
```

→ `SCYLLA_CPUSET=0-15` (all of die 0, private L3),
`WORKLOAD_CPUSET=18-31` (die 1 minus one core left for the OS). Other
machines number differently — on many Intel parts the sibling of CPU 0
is CPU 16, not CPU 1 — so derive the ranges from **your** `lscpu -e`
output, never copy an example.

### Commitlog durability

The single-node ScyllaDB runs with **batch** commitlog sync by default,
mirroring the GKE validators (`scyllaCommitlogSync: batch`,
`scyllaCommitlogSyncBatchWindowMs: 2`): writes are fsynced to disk
before being acknowledged, at the cost of a small (2 ms) batching
latency. Override via `SCYLLA_COMMITLOG_SYNC` /
`SCYLLA_COMMITLOG_SYNC_BATCH_WINDOW_MS` (set `SCYLLA_COMMITLOG_SYNC=periodic`
to trade durability for throughput).

### How far can a single host go?

With the cache defaults at GKE parity, ScyllaDB pinned to dedicated
cores, `--overprovisioned 0`, batch commitlog, and ScyllaDB data on a
fast (ideally XFS, see below) disk, the single-host stack scales
**vertically** toward GKE-class throughput on a big enough machine. What
it **cannot** match is GKE's physical isolation: there, ScyllaDB gets
its own dedicated nodes with perftune CPU pinning, IRQ steering off the
Scylla cores, and a separate kernel/NIC, while here it shares the kernel,
disks, and NICs with the shards and proxy. The `SCYLLA_CPUSET` /
`WORKLOAD_CPUSET` pair approximates the CPU half of that; the rest is a
hard limit of single-host co-tenancy. For full isolation and HA, use the Helm path with a real
ScyllaDB cluster.

## Upgrading .env safely

When a new release adds configuration variables, merge them in without
losing your existing values:

```bash
./scripts/upgrade-env.sh           # or: ./scripts/upgrade-env.sh --dry-run
```

This rebuilds `.env` from the template, preserves every value you set,
appends any new variables (commented out, so nothing changes behavior
by itself), and backs up the old file to
`.env.backup.YYYYMMDD-HHMMSS`.

No data — Docker volumes, `server.json`, `genesis.json` — is touched.

## Stopping & resetting

```bash
cd docker
docker compose down                  # keep data
docker compose down -v               # also wipe Scylla volume (⚠ loses sync)
rm -f genesis.json server.json validator-config.toml  # also wipe keys + genesis
```

## XFS data directory (optional)

ScyllaDB performs best on XFS. If you have a dedicated XFS partition
mounted at `/mnt/scylla`, pass it to `deploy-validator.sh`:

```bash
./scripts/deploy-validator.sh --xfs-path /mnt/scylla \
  validator.example.com admin@example.com
```

That emits a `docker-compose.override.yml` that bind-mounts
`/mnt/scylla/scylla-data` into the Scylla container.

If the machine has more than one NVMe drive, dedicate one to the
ScyllaDB data directory (XFS or not): compaction is the dominant I/O
load on a validator, and a drive that the OS, logs, and Docker images
never touch removes the last source of disk contention.

## Observability (optional)

The Linera binary can push metrics/logs/traces to an OTLP-compatible
backend. Enable by uncommenting the matching block in `.env`:

```bash
PROMETHEUS_OTLP_URL=https://prometheus.example.com/otlp
PROMETHEUS_OTLP_USER=…
PROMETHEUS_OTLP_PASS=…
```

Restart the stack after editing. The Watchtower-driven auto-update
loop also picks up config changes on restart.

## Limitations

- Single-validator, single-host. Compose drives one Docker Engine on
  one machine: no scheduling across hosts, no replication, no HA — if
  the box dies, the validator is down until you restore it. Docker
  Swarm is not an escape hatch: swarm services cannot pin CPUs at all
  ([moby/moby#30477](https://github.com/moby/moby/issues/30477)), so
  scaling out through Swarm silently drops the ScyllaDB isolation
  configured above. The supported multi-machine path is the Helm chart.
- A single validator being offline is an event the network tolerates —
  BFT consensus keeps making progress without it. What a single-host
  operator should plan for is **recovery time**, not single-box HA:
  know where the replacement hardware comes from, and that losing the
  ScyllaDB volume means re-syncing from genesis.
- ScyllaDB runs as a single node (RF=1). Safe for dev and single-validator
  production; you need a real Scylla cluster for higher availability.
- Vertical scaling only: with GKE-parity caches and dedicated-core ScyllaDB
  pinning (see **Dedicated-hardware ScyllaDB tuning**) the stack scales up
  toward GKE-class throughput, but cannot match GKE's dedicated-node Scylla
  isolation (separate kernel/NICs, perftune, IRQ steering) — ScyllaDB here
  always shares the host with the shards and proxy.
- `docker compose down -v` wipes ScyllaDB — you'll have to re-sync from
  genesis on the next start.
