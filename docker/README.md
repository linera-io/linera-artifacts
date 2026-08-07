# linera-validator — docker compose

By default, this directory deploys a production single-host validator stack: Caddy (TLS) → linera-proxy → N linera-server shards → ScyllaDB, with Watchtower for auto-updates and a one-shot `scylla-setup` container for host tuning.

An optional `docker-compose.remote-scylla.yaml` overlay allows ScyllaDB to run on a separate host while keeping the validator services in the main stack.

For full operator docs see https://docs.infra.linera.net/:

* [Quickstart](https://docs.infra.linera.net/QUICKSTART/)
* [Hardware requirements](https://docs.infra.linera.net/HARDWARE/)
* [Docker Compose reference](https://docs.infra.linera.net/DOCKER-COMPOSE/)
* [Post-setup operations](https://docs.infra.linera.net/POST-SETUP/)

## Files

| File                                   | Purpose                                                                                 |
| -------------------------------------- | --------------------------------------------------------------------------------------- |
| `docker-compose.yaml`                  | Core stack: web, ScyllaDB, proxy, 4 shards, and Watchtower. Required.                   |
| `docker-compose.remote-scylla.yaml`    | Optional overlay: use an external ScyllaDB host instead of the local ScyllaDB services. |
| `docker-compose.alloy.yaml`            | Optional overlay for remote Prometheus/Loki/Tempo telemetry.                            |
| `docker-compose.local-monitoring.yaml` | Optional local Prometheus + Grafana stack.                                              |
| `.env.production.template`             | Reference `.env`. Copy to `.env`, or use `scripts/deploy-validator.sh`.                 |
| `dashboards/`                          | Grafana dashboards auto-loaded by the local-monitoring overlay. `performance.json` is the one Linera watches for its own validators. |
| `recording.rules.yaml`                 | Recording rules backing `dashboards/performance.json`. Loaded via `prometheus.yaml`.    |
| `Caddyfile`                            | TLS and reverse-proxy configuration.                                                    |

## Quickstart

```bash
# from the repo root:
./scripts/deploy-validator.sh validator.example.com admin@example.com
```

The script prepares `.env`, downloads `genesis.json`, generates `server.json`, and starts the stack.

For manual or advanced deployments, including remote ScyllaDB and monitoring overlays, see the [Docker Compose reference](https://docs.infra.linera.net/DOCKER-COMPOSE/).

## Remote ScyllaDB

To run ScyllaDB on a separate host, use the `docker-compose.remote-scylla.yaml` overlay and set `SCYLLA_HOST` to an address reachable from the validator host:

```bash
SCYLLA_HOST=10.77.77.1 \
docker compose \
  -f docker-compose.yaml \
  -f docker-compose.remote-scylla.yaml \
  up -d
```

The overlay disables the local `scylla` and `scylla-setup` services, removes Compose dependencies on the local database, and maps the existing `scylla` hostname used by the proxy and shards to the remote host.

`SCYLLA_HOST` is required: leaving it unset fails immediately with an error
rather than starting a stack that cannot reach its database. The overlay relies
on the `!reset` and `!override` merge tags, so it needs a Docker Compose recent
enough to support them — if yours does not, `docker compose config` will report
the tags as unknown.

Do not add `--profile local-scylla` to bring the local database back. That
combination starts ScyllaDB but leaves the health-check waits removed and still
resolves `scylla` to `$SCYLLA_HOST`. To use the local database, simply omit this
overlay.

The remote ScyllaDB endpoint should be exposed only over a trusted private network, such as a private VLAN or WireGuard tunnel.

## Tuning

Service limits, ports, image tags, and ScyllaDB settings are configured through `.env`.

Important variables include:

* `LIMIT_CPUS_*` / `LIMIT_MEM_*` — cgroup CPU and memory budgets per service.
  Defaults target a 16-core / 64 GB host.
* `LIMIT_CPUS_SCYLLA` — also drives ScyllaDB's `--smp`. Increasing it on
  existing data is fine; **reducing it requires a full data wipe.**
* `LIMIT_MEM_SCYLLA` — cgroup memory limit for ScyllaDB. ScyllaDB reads this
  directly via cgroup and reserves its own headroom (we do not pass
  `--memory`). To grow ScyllaDB, just raise this number.

See [`.env.production.template`](.env.production.template) for the complete configuration and inline documentation.
