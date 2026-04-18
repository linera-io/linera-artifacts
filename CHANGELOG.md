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
- CI workflows: yamllint, shellcheck, helm-lint, helm-unittest (69
  tests across 16 suites), chart-testing, kubeconform, helm-docs
  drift check, plus a cosign-signed OCI release on SemVer tags.

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
