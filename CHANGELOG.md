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
