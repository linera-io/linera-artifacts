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
4. Renders `.env` from `.env.production.template`
5. Starts the stack with `docker compose up -d --wait`

Options:

```text
--skip-genesis      Don't download — assume genesis.json is already there.
--force-genesis     Re-download even if a copy exists.
--image-tag TAG     Override the linera image tag (default: testnet_conway_release).
--linera-image REF  Override the full image reference.
--xfs-path PATH     Bind-mount this XFS dir for ScyllaDB data.
--num-shards N      Number of shards (must match docker-compose.yml services).
--dry-run           Print what would happen, change nothing.
```

## Manual deploy

If you prefer to do each step yourself:

```bash
cd docker

# 1. Env file from template
cp .env.production.template .env
#    Edit DOMAIN, ACME_EMAIL, VALIDATOR_NAME, VALIDATOR_KEY.

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
Key variables:

| Variable              | Default                               | Notes                                                                                      |
|-----------------------|---------------------------------------|--------------------------------------------------------------------------------------------|
| `DOMAIN`              | `your-domain.example.com`             | Public hostname. Caddy obtains a Let's Encrypt cert for this.                              |
| `ACME_EMAIL`          | `admin@example.com`                   | Registered with Let's Encrypt.                                                             |
| `GENESIS_URL`         | `…/testnet-conway/genesis.json`       | Public genesis file to use.                                                                |
| `LINERA_IMAGE`        | `…/linera-public-registry/linera:testnet_conway_release` | Upstream image. Update to change network compatibility.                |
| `SCYLLA_DEVELOPER_MODE` | `0`                                 | Set to `1` only for local testing (skips ScyllaDB io_setup checks).                       |
| `STORAGE_REPLICATION_FACTOR` | `1`                            | Matches single-node Scylla. Do not change without a Scylla cluster.                         |
| `PROXY_PORT`          | `19100`                               | Host port the proxy is bound to (behind Caddy on 443).                                     |
| `LIMIT_CPUS_SHARD_N` / `LIMIT_MEM_SHARD_N` | per-shard                | Resource limits (honored in swarm or with `docker compose --compatibility`).               |
| `LINERA_EXECUTION_STATE_CACHE_SIZE` | `5000`                  | Upstream default is 10000 — lower to save RAM.                                             |
| `LINERA_BLOCK_CACHE_SIZE` | `2500`                            | Upstream default is 5000 — lower to save RAM.                                              |
| `WATCHTOWER_INTERVAL` | `30`                                  | Seconds between image-update checks.                                                       |
| `LIMIT_CPUS_SCYLLA`   | `4`                                   | CPU cgroup budget for ScyllaDB. Also drives `--smp` (shard count). See **ScyllaDB sizing** below. |
| `LIMIT_MEM_SCYLLA`    | `30G`                                 | Memory cgroup budget for the ScyllaDB container. ScyllaDB reads this and reserves its own headroom — see below. |
| `SCYLLA_SMP`          | `${LIMIT_CPUS_SCYLLA}`                | Override the shard count independently of the CPU limit. Rarely needed.                    |

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

- Single-validator, single-host. No HA, no replication across machines.
- ScyllaDB runs as a single node (RF=1). Safe for dev and single-validator
  production; you need a real Scylla cluster for higher availability.
- `docker compose down -v` wipes ScyllaDB — you'll have to re-sync from
  genesis on the next start.
