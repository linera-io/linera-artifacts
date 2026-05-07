# linera-validator — docker compose

Production single-host validator stack: Caddy (TLS) → linera-proxy →
N linera-server shards → ScyllaDB, with Watchtower for auto-updates
and a one-shot `scylla-setup` container that tunes host sysctls.

For full operator docs see <https://docs.infra.linera.net/>:

- [Quickstart](https://docs.infra.linera.net/QUICKSTART/)
- [Hardware requirements](https://docs.infra.linera.net/HARDWARE/)
- [Docker Compose reference](https://docs.infra.linera.net/DOCKER-COMPOSE/)
- [Post-setup operations](https://docs.infra.linera.net/POST-SETUP/)

## Files

| File                                  | Purpose                                                   |
|---------------------------------------|-----------------------------------------------------------|
| `docker-compose.yml`                  | Core: web, scylla, proxy, 4 shards, watchtower. Required. |
| `docker-compose.alloy.yml`            | Optional overlay: push metrics/logs/traces to a remote Prometheus/Loki/Tempo. |
| `docker-compose.local-monitoring.yml` | Optional overlay: local Prometheus + Grafana on the host. |
| `.env.production.template`            | Reference `.env`. Copy to `.env` (or use `scripts/deploy-validator.sh`). |
| `dashboards/`                         | Grafana dashboards auto-loaded by the local-monitoring overlay. |
| `Caddyfile`                           | Caddy config (TLS + reverse-proxy to linera-proxy).       |

## Quickstart

```bash
# from the repo root:
./scripts/deploy-validator.sh validator.example.com admin@example.com
```

That populates `.env` from the template, downloads the network's
`genesis.json`, generates your `server.json`, and brings the stack up.
For manual / advanced setup (custom genesis, larger hosts, opt-in
monitoring overlays) see the
[Docker Compose reference](https://docs.infra.linera.net/DOCKER-COMPOSE/).

## Tuning

Every limit, port, image tag, and ScyllaDB knob is configurable via
`.env`. Key variables:

- `LIMIT_CPUS_*` / `LIMIT_MEM_*` — cgroup CPU / memory budgets per
  service. Defaults target a 16-core / 64 GB host.
- `LIMIT_CPUS_SCYLLA` — also drives ScyllaDB's `--smp`. Increasing it
  on existing data is fine; reducing it requires a full data wipe.
- `LIMIT_MEM_SCYLLA` — cgroup memory limit for ScyllaDB. ScyllaDB
  reads this directly via cgroup and reserves its own headroom (we do
  not pass `--memory`). To grow ScyllaDB just raise this number.

See [`.env.production.template`](.env.production.template) for the
full list with inline comments.
