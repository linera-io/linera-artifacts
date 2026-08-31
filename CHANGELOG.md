# Changelog

All notable operator-facing changes are documented here.

Versions follow [Semantic Versioning](https://semver.org/):

- **Chart version** (`version` in `Chart.yaml`) bumps on any change to
  templates, defaults, or required values.
- **App version** (`appVersion`) tracks the supported Linera binary
  release. Charts pin to a specific Linera tag (`testnet_conway_release`
  today) by default — override `image.tag` if you need a different one.

Release channels:

- `testnet_conway_release` — **current production**, tracks the
  `testnet_conway` branch of `linera-protocol`.
- SemVer tags (`vX.Y.Z`) — snapshot releases pushed to the OCI registry
  along with cosign signatures.

---

## [0.2.3] — 2026-08-31

Compose-stack release; no chart templates or values changed since 0.2.2.
Everything below concerns `docker/`, `scripts/` and the monitoring the
compose stack ships.

### Fixed

- **`deploy-validator.sh` aborted with `linera_image: unbound variable`.**
  The single `linera` image was split upstream into `linera-validator` and
  `linera-client`, and one reference to the old variable survived. Every
  deployment on 0.2.0 through 0.2.2 hit this — use this release or later.
- **Watchtower was updating every container on the host.** It ran without
  `--label-enable`, which is the flag that makes
  `com.centurylinklabs.watchtower.enable` mean anything, so the labels on the
  proxy and shards were decorative. ScyllaDB was spared only because
  `SCYLLA_IMAGE` pins an immutable tag.
- **The shards had no healthcheck.** Only `scylla` and `proxy` did, so with
  `restart: unless-stopped` Docker restarted a shard only when its process
  exited — a shard that stayed up and failed every request was never noticed.
  They now carry the same TCP probe and timings as the chart's shard
  `livenessProbe`.
- **Every alert in `docker/alerts.rules.yaml` was dead.** Four selected job
  names the scrape config never produced (`shards`/`proxy` rather than
  `linera-shard`/`linera-proxy`; PromQL anchors `=~`), one queried a metric
  that does not exist, and ScyllaDB was not scraped at all. A silent alert set
  read as a healthy validator. ScyllaDB is now a scrape target on its default
  Prometheus port, and CI checks that every rule's job selector resolves
  against the scrape config — `promtool check rules` passes on a rule that
  selects a job nobody scrapes, which is how these shipped.
- **`LineraProxyHighLatency` used the wrong unit.** `proxy_request_latency` is
  recorded in milliseconds, so the threshold is 2000, not 2.

### Changed

- **The shard count is configurable and now defaults to 8**, matching
  testnet-conway; it was fixed at 4. `--num-shards` takes 4–8 and
  `deploy-validator.sh` writes the matching `COMPOSE_PROFILES`.

  **Existing deployments are unaffected.** Shards 0–3 carry no profile, so a
  stack that predates this keeps the four it already ran. The count lives in
  `server.json`, which is never regenerated (that would rotate your signing
  key), so the script reads it back from there on every re-run and refuses a
  `--num-shards` that disagrees rather than starting shards that panic on
  boot. Growing an existing validator is a resharding — see
  [Changing the shard count](docs/DOCKER-COMPOSE.md#changing-the-shard-count).
- **Prometheus and Alloy discover shards through the Docker daemon** instead
  of listing them, reading the index from each container's new `linera.shard`
  label. Neither file names a shard, so neither alerts on shards a smaller
  deployment does not run. Prometheus now mounts the Docker socket read-only.
- **ScyllaDB drains before it stops.** A `pre_stop` hook runs `nodetool drain`
  and `stop_grace_period` rises to 900s, mirroring what scylla-operator does
  on Kubernetes. Docker's 10s default was forcing a SIGKILL mid-flush.
- Hardware guidance now budgets 8 shards at 6 GiB rather than 4 at 12 GiB.
  The total is the same 48 GiB, so the reference box is still 16 cores /
  128 GB.

### Added

- End-to-end tests for `deploy-validator.sh` that run it for real against a
  stubbed docker and assert the files it writes. `--dry-run` returns early
  from the three functions that produce a validator's config, so a dry-run
  smoke test could not see a wrong image or a mangled `.env` — both of which
  shipped under exactly that gap.
- CI: `promtool` on the rule files, rule-selector resolution, and shellcheck
  over every tracked script rather than a glob that matched nothing.

## [Unreleased]

Initial public release. This section will be dated and versioned on
the first tag.

### Changed

- Every YAML file now uses the `.yaml` extension. `.yaml` is the extension
  registered as preferred in RFC 9512 and recommended by the YAML project
  since 2006; `.yml` is a DOS-era three-character relic. More concretely,
  RFC 9512 §3.3 names mixing both extensions in one place as the actual
  interoperability hazard, and this repo was mixing them 64 to 15.

  If you pass compose files explicitly with `-f`, update the paths:
  `docker-compose.yml` → `docker-compose.yaml`, and likewise for the
  `alloy` and `local-monitoring` overlays.

  `artifacthub-repo.yml` is deliberately unchanged in all three charts:
  Artifact Hub specifies that exact filename, and `.yaml` is not documented
  as accepted.

  `linera-validator` 0.1.7 → 0.1.8 and `linera-validator-stack` 0.1.9 →
  0.1.10 come along for the ride. The only in-chart change is one
  `{{/* … */}}` comment that named a renamed file, so rendered output is
  byte-identical; the bump is what `check-version-increment` requires of
  any touched chart, not a behaviour change.

### Added

- Helm chart `linera-validator` — core validator (shards + proxies).
- Helm chart `linera-block-exporter` — optional side-car that reads
  blocks from a validator's ScyllaDB and pushes them to an indexer
  over gRPC. Recommended on every validator: it lets the wider
  network reconstruct chain history.
- Helm chart `linera-validator-stack` — umbrella that bundles the
  validator plus a `ScyllaCluster` custom resource.
- Docker compose stack (`docker/`) mirroring the chart shape
  for single-host validator deployments. Includes Caddy (TLS via
  Let's Encrypt), scylla-setup (host sysctl tuning), and Watchtower
  (label-driven auto-updates).
- `scripts/deploy-validator.sh` — one-command bootstrap for the compose
  stack.
- `scripts/upgrade-env.sh` — merge new template variables into an
  existing `.env` without losing settings.
- `scripts/install-prereqs.sh` — install `scylla-operator` (and
  optionally `cert-manager`) for the Helm path.
- `devspace.yaml` — CNCF DevSpace configuration for the local chart
  dev loop on kind.
- CI workflows: yamllint, shellcheck, helm-lint, helm-unittest (80
  tests across 17 suites), chart-testing, kubeconform, helm-docs
  drift check, plus a cosign-signed OCI release on SemVer tags.
- `linera-validator` observability, opt-in and off by default:
  - ScyllaDB recording rules (`templates/scylla-recording-rules.yaml`,
    122 `scylla:*`/`cql:*` aggregates: coordinator read/write/CAS
    latency percentiles, CQL rates, error rates, per-table latencies,
    Scylla Manager progress). Gated behind both `prometheusRule.enabled`
    and `prometheusRule.recordingRules.enabled`, alongside the existing
    linera recording rules.
  - Extra alert groups gated by per-group `prometheusRule.alerts.*`
    toggles: validator request latency, chain correctness
    (`InboxGapDetected` / `CorruptedChainState`), block-production
    stalled, ScyllaDB latency/down/restart, Scylla Manager backups,
    and PVC capacity. Self-monitoring operators enable the ones whose
    metrics they scrape.

- Optional observability overlays for the compose stack (off by
  default; most validators run without):
  `docker-compose.alloy.yml` (Grafana Alloy + cAdvisor pushing
  metrics/logs/traces to a remote OTLP backend) and
  `docker-compose.local-monitoring.yml` (Prometheus + Grafana +
  Loki + Tempo + alert rules on the same host). See
  [`docs/OBSERVABILITY.md`](docs/OBSERVABILITY.md).
- Nix flake + `.envrc` + Makefile + Justfile for a reproducible
  tooling shell. charm.sh `gum` / `glow` are wired up as optional
  dependencies — recipes fall back gracefully when they aren't
  available.
- `docs/examples/cert-manager-clusterissuer.yaml` — ACME staging +
  production ClusterIssuers for use with the Gateway API.
