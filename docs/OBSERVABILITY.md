# Observability

Observability is **opt-in**. The default validator stack ships
**no** observability containers — most operators either go without
or scrape the validator's `/metrics` endpoints with their own
external Prometheus.

Two independent opt-in feature flags. They compose freely (use
none, one, or both):

- **Alloy push** (`--with-alloy`) — lightweight; Alloy + cAdvisor
  forward metrics/logs/traces to a remote Prometheus / Loki / Tempo
  you already operate. Recommended when you have (or can point at) a
  central observability backend.
- **Local monitoring** (`--with-local-monitoring`) — opt-in heavy
  mode; the validator host also runs Prometheus + Grafana + Loki +
  Tempo + alert rules. Useful for self-contained dashboards on the
  same box.

Combinations:

| `--with-alloy` | `--with-local-monitoring` | Result                                                          |
|----------------|---------------------------|-----------------------------------------------------------------|
| no             | no                        | **Default.** No observability containers. /metrics still on :21100. |
| yes            | no                        | Push to your remote backend (recommended).                      |
| no             | yes                       | Local Prometheus + Grafana + Loki + Tempo + alerts only.        |
| yes            | yes                       | Both — local dashboards AND remote forwarding.                  |

## What Linera itself exposes (always on)

Every Linera service exposes Prometheus metrics on port `21100` and
OTLP traces via the `LINERA_OTLP_EXPORTER_ENDPOINT` env var (already
wired by the chart and compose). Logs go to stdout in structured
JSON when `RUST_LOG` is set (default).

These endpoints are visible whether you run the observability
overlays or not — point any external scraper at them.

## Docker Compose

### Default — no observability containers

```bash
./scripts/deploy-validator.sh validator.example.com admin@example.com
```

You still get the `/metrics` endpoint on port `21100` of every
service. Hook your own Prometheus to it.

### Alloy push (recommended for operators with a central backend)

```bash
./scripts/deploy-validator.sh --with-alloy \
  validator.example.com admin@example.com
```

Fill the push endpoints in `.env`:

```ini
PROMETHEUS_OTLP_URL=https://prometheus.example.com/otlp
PROMETHEUS_OTLP_USER=...
PROMETHEUS_OTLP_PASS=...
LOKI_PUSH_URL=https://loki.example.com/loki/api/v1/push
LOKI_PUSH_USER=...
LOKI_PUSH_PASS=...
TEMPO_OTLP_URL=https://tempo.example.com/tempo/otlp
TEMPO_OTLP_USER=...
TEMPO_OTLP_PASS=...
```

Without those set Alloy silently drops data — there's nowhere to
forward it.

### Local monitoring (heavy opt-in)

Brings up Prometheus + Grafana + Loki + Tempo + alert rules on the
host:

```bash
./scripts/deploy-validator.sh --with-local-monitoring \
  validator.example.com admin@example.com
```

Combine with `--with-alloy` to push the same data out to a remote
backend in parallel:

```bash
./scripts/deploy-validator.sh --with-alloy --with-local-monitoring \
  validator.example.com admin@example.com
```

Ports:

- `3000` — Grafana (login `admin` / `${GRAFANA_ADMIN_PASSWORD:-admin}`)
- `9090` — Prometheus
- `3100` — Loki
- `3200` — Tempo
- `12345` — Alloy UI

Dashboards in [`docker/dashboards/`](https://github.com/linera-io/linera-artifacts/tree/main/docker/dashboards); drop a
new `.json` and re-`docker compose up` to pick it up. Alert rules in
[`docker/alerts.rules.yml`](https://github.com/linera-io/linera-artifacts/blob/main/docker/alerts.rules.yml).

### Layering it yourself

Without the deploy script:

```bash
cd docker

# Default (off)
docker compose -f docker-compose.yml up -d

# Alloy push
docker compose -f docker-compose.yml -f docker-compose.alloy.yml up -d

# Local monitoring
docker compose -f docker-compose.yml -f docker-compose.local-monitoring.yml up -d

# Both — alloy pushes AND on-box dashboards
docker compose \
  -f docker-compose.yml \
  -f docker-compose.alloy.yml \
  -f docker-compose.local-monitoring.yml \
  up -d
```

## Helm

The Helm chart follows the same **opt-in / composable** philosophy
as the compose stack, but at finer granularity. The chart itself
ships **no** observability stack — Prometheus, Grafana, Loki, Tempo
are your cluster's concern. The chart only emits the CRs your
existing stack needs to start scraping, alerting, and rendering
dashboards.

Three independent flags. Enable any combination:

| Flag                      | Emits                                                  | Requires                                                     |
|---------------------------|--------------------------------------------------------|--------------------------------------------------------------|
| `serviceMonitor.enabled`  | `ServiceMonitor` targeting shards + proxy `/metrics`.  | Prometheus Operator (or Alloy configured to discover SMs).   |
| `prometheusRule.enabled`  | `PrometheusRule` with default Linera alerts + yours.   | Prometheus Operator + `PrometheusRule` CRD.                  |
| `dashboards.enabled`      | One `ConfigMap` per JSON dashboard, sidecar-labelled.  | Grafana with the dashboard sidecar enabled.                  |

Defaults are all `false` — a bare `helm install` produces no
observability resources, same as a bare `docker compose up` produces
no observability containers.

```yaml
# my-values.yaml — turn on everything
serviceMonitor:
  enabled: true
  labels:
    release: prometheus        # match your Prometheus's serviceMonitorSelector
prometheusRule:
  enabled: true
dashboards:
  enabled: true
```

### Remote push (Alloy / agent-based forwarding)

The Helm chart does **not** ship an Alloy sidecar — that's a cluster
concern, not a per-chart concern. If you want the same "push to a
remote Prometheus / Loki / Tempo" behaviour the compose
`--with-alloy` flag gives you, install Alloy (or the Grafana Agent,
or OpenTelemetry Collector) as a separate release in the cluster and
point it at the ServiceMonitor created by
`serviceMonitor.enabled=true`.

### Customising alerts

Extend the shipped rules without forking the chart:

```yaml
prometheusRule:
  enabled: true
  extraRules:
    - alert: MyCustomAlert
      expr: up{...} == 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: …
```

### Dashboards shipped with the chart

`dashboards.enabled=true` emits one `ConfigMap` per JSON file under
[`helm/linera-validator/dashboards/`](https://github.com/linera-io/linera-artifacts/tree/main/helm/linera-validator/dashboards),
recursively, labelled for the Grafana sidecar. Current set:

- `linera/general.json` — validator overview (proxy + shard health, rps, error rate)
- `linera/execution.json` — execution layer metrics
- `linera/views.json` — view cache / materialisation metrics
- `linera/storage/storage.json` — generic storage layer metrics
- `linera/storage/rocksdb.json` — RocksDB-specific counters (when dual-store enabled)
- `linera/storage/scylladb.json` — ScyllaDB-specific counters
- `linera/vms/ethereum.json` — EVM-runtime dashboards
- `profiling/cpu.json`, `profiling/jemalloc-memory.json` — continuous-profiling views (Pyroscope)
- `scylla/scylla-{overview,detailed,advanced,cql,ks,os,alternator}.json` — upstream ScyllaDB dashboards (tag 6.2)
- `scylla-manager/scylla-manager.json` — ScyllaDB Manager dashboard (tag 3.4)

Drop additional JSON files into the same directory and re-run
`helm upgrade` — the chart picks them up automatically.
