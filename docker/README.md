# linera-validator — docker compose

Single-node validator stack for development, demos, or local CI. The
service shape mirrors the `linera-validator` Helm chart so the same
genesis + signing-key files work in both worlds.

## Components

| Service        | Image                          | Role                                    |
|----------------|--------------------------------|-----------------------------------------|
| `network-init` | `linera-network-init`          | One-shot: generate `genesis.json` + `server_1.json`. Run with `--profile init`. |
| `scylla`       | `scylladb/scylla`              | Storage backend.                        |
| `storage-init` | `linera`                       | One-shot: initialize the validator's database from genesis. |
| `shard-{0..3}` | `linera` (`linera-server run`) | Validator shards.                       |
| `proxy`        | `linera` (`linera-proxy`)      | Client-facing gRPC proxy.               |

## Quickstart

```bash
cp .env.example .env
mkdir -p network-config

# 1. Generate genesis + server config (writes to ./network-config/).
docker compose --profile init up network-init

# 2. Start the stack.
docker compose up -d

# 3. Tail the logs.
docker compose logs -f proxy
```

Client traffic hits `localhost:19100` (gRPC). Prometheus metrics are
on `localhost:21100`.

## Stopping & resetting

```bash
docker compose down                # keep data
docker compose down -v             # also wipe Scylla volume
rm -rf network-config              # also wipe genesis + signing key
```

## Tuning

Knobs live in `.env`:

- `LINERA_VERSION` — must point to a published linera image tag.
- `NUM_SHARDS` — number of shards. Default is 4. **If you change this
  you must also add/remove `shard-N` blocks in `docker-compose.yml`**
  (compose has no native fan-out for ordinal-aware services).
- `SCYLLA_SMP` / `SCYLLA_MEMORY` — bump for benchmarking; defaults are
  conservative for laptops.

## Limitations

This setup is single-validator and not intended for production:

- One Scylla node, no replication.
- No TLS termination on the proxy port.
- No persistence for shards beyond Scylla's volume.
- Resource limits (`deploy.resources`) intentionally omitted — they're
  ignored by the default Compose runtime and configurable per host.

For a real deployment use the Helm chart (`helm/linera-validator/`).
