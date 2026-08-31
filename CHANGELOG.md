# Changelog

All notable operator-facing changes to this repository are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Two version numbers

Repository tags (`vX.Y.Z`) and chart versions are **not** the same number, and
the sections below are organised by repository tag.

- **Repository tag** — what you check out, and the only thing that publishes.
  `helm package --version` takes it straight from the tag, so a tag is what
  ships all three charts to `ghcr.io/linera-io/charts/` at that version.
  Merging to `main` publishes nothing.
- **Chart version** (`version` in `Chart.yaml`) — bumps on any change to
  templates, defaults, or required values, and is what `ct lint` enforces.
  Chart versions 0.1.4, 0.1.5 and 0.2.1 exist in history without a matching
  repository tag.
- **App version** (`appVersion`) — the supported Linera binary release. Charts
  pin `testnet_conway_release` by default; override `image.tag` for another.

Release channels:

- `testnet_conway_release` — **current production**, tracks the
  `testnet_conway` branch of `linera-protocol`.
- SemVer tags (`vX.Y.Z`) — snapshot releases pushed to the OCI registry
  along with cosign signatures.

---

## [Unreleased]

Nothing yet.

## [0.3.0] — 2026-08-31

### Changed

- **BREAKING (chart):** `linera-validator` now defaults `shards.replicas` to
  **8**, matching testnet-conway; it was 4. Any release relying on the old
  default must pin `shards.replicas: 4` **before** upgrading. Each pod runs
  `--shard $ORDINAL` against the shard list in your server config, which the
  chart never generates, so a pod whose ordinal is past the end of that list
  panics on boot.

  Where the chart can see that list — an inline `validator.serverConfigData` —
  a mismatch now fails at render with both counts named. With
  `validator.existingSecret` it cannot: `NOTES.txt` says so rather than
  implying a check that does not exist.

  `linera-validator` 0.2.1 → 0.3.0, `linera-validator-stack` 0.2.2 → 0.3.0
  along with its subchart pin.

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

## [0.2.2] — 2026-08-19

### Fixed

- `linera-validator-stack` creates the `ScyllaCluster` before the resources
  that block on it, so a fresh install converges instead of stalling.

### Changed

- `ClientTrafficPolicy` now sizes the downstream HTTP/2 windows.
- `linera-validator-stack` 0.2.1 → 0.2.2, subchart pin and READMEs regenerated.

## 0.2.1 — not released

Chart version only; no repository tag was cut.

## [0.2.0] — 2026-08-11

### Changed

- **BREAKING (charts):** `image` split into `validatorImage` / `exporterImage`,
  for symmetry with `clientImage`. Every values file, test and example follows
  the rename. `linera-validator` and `linera-validator-stack` → 0.2.0.
- **Every YAML file now uses the `.yaml` extension**, enforced in CI. `.yaml`
  is the extension registered as preferred in RFC 9512 and recommended by the
  YAML project since 2006; RFC 9512 §3.3 names *mixing* both extensions in one
  place as the actual interoperability hazard, and this repo was mixing them
  64 to 15.

  If you pass compose files explicitly with `-f`, update the paths:
  `docker-compose.yml` → `docker-compose.yaml`, and likewise for the `alloy`
  and `local-monitoring` overlays.

  `artifacthub-repo.yml` is deliberately unchanged in all three charts:
  Artifact Hub specifies that exact filename, and `.yaml` is not documented as
  accepted.
- `docker-compose.remote-scylla.yaml` now requires `SCYLLA_HOST` rather than
  defaulting it, and the ScyllaDB tuning warnings are back.

## [0.1.9] — 2026-07-08

### Fixed

- `linera-validator` delivers the shard block/execution-state cache sizes via
  environment rather than `run` args. They are top-level flags on newer
  `linera-server`, so passing them as `run` args failed on those binaries.

## [0.1.8] — 2026-07-07

### Added

- `linera-validator` gains a `useComponentPrefix` toggle. Default `false`
  gives clean `proxy` / `shards` / `proxy-internal` names; legacy deployments
  (the OVH `k8s-validator`) pin it `true`.

## [0.1.7] — 2026-07-03

### Fixed

- `linera-validator-stack` creates the `scylla` namespace. The chart rendered a
  `ScyllaCluster` into it but never created it, so a fresh cluster failed with
  `namespaces "scylla" not found`.

## [0.1.6] — 2026-07-02

### Added

- `linera-validator` supports `image.digest` for immutable, content-addressed
  pins.
- ScyllaDB recording rules and expanded validator alert coverage in
  `linera-validator`.
- Scylla Guaranteed-QoS `agentResources`, batch commitlog sync, and an optional
  perftune `NodeConfig` in `linera-validator-stack`.

### Changed

- The Docker Compose validator is tuned for GKE-class performance: full
  storage-cache parity, batch commitlog, and optional CPU pinning.
- Hardware guidance corrected to the actual reference topology (2 × 8 vCPU /
  64 GB), with explicit disk IOPS and throughput requirements. The
  light-testing tier and the SATA SSD hedge are gone.

## 0.1.4 and 0.1.5 — not released

Chart versions only; no repository tags were cut.

## [0.1.3] — 2026-05-20

### Fixed

- The edge proxy no longer aborts long-lived gRPC.
- `deploy-validator.sh` emits the full `validator,account` key pair on a
  re-run, and encodes `account_key` with its BCS discriminant byte in hex.
- `--memory` dropped from the ScyllaDB args so the cgroup limit is
  auto-detected. Passing it explicitly overrode ScyllaDB's own headroom and
  caused "not enough memory" crashes.

### Changed

- `chain-worker-ttl` and conntrack guidance aligned with the GKE validators.
- The migration guide is replaced by a POST-SETUP page.

## [0.1.2] — 2026-05-04

### Added

- Brand logo and `values.schema.json` for all charts.

### Changed

- All charts bumped to 0.1.2.

## [0.1.1] — 2026-05-01

### Fixed

- `linera-validator`: `liteCertificateCacheSize` renamed to
  `certificateCacheSize`.

## [0.1.0] — 2026-05-01

Initial public release.

### Added

- Helm chart `linera-validator` — core validator (shards + proxies).
- Helm chart `linera-block-exporter` — optional side-car that reads blocks from
  a validator's ScyllaDB and pushes them to an indexer over gRPC. Recommended
  on every validator: it lets the wider network reconstruct chain history.
- Helm chart `linera-validator-stack` — umbrella bundling the validator plus a
  `ScyllaCluster` custom resource.
- Docker compose stack (`docker/`) mirroring the chart shape for single-host
  validator deployments. Includes Caddy (TLS via Let's Encrypt), scylla-setup
  (host sysctl tuning), and Watchtower.
- `scripts/deploy-validator.sh` — one-command bootstrap for the compose stack.
- `scripts/upgrade-env.sh` — merge new template variables into an existing
  `.env` without losing settings.
- `scripts/install-prereqs.sh` — install `scylla-operator` (and optionally
  `cert-manager`) for the Helm path.
- `devspace.yaml` — CNCF DevSpace configuration for the local chart dev loop on
  kind.
- CI: yamllint, shellcheck, helm-lint, helm-unittest, chart-testing,
  kubeconform, a helm-docs drift check, and a cosign-signed OCI release on
  SemVer tags.
- `linera-validator` observability, opt-in and off by default: ScyllaDB
  recording rules and extra alert groups, each behind its own toggle.
- Artifact Hub registration: per-chart `artifacthub-repo.yml` claim files under
  the `linera-io` organisation.

[Unreleased]: https://github.com/linera-io/linera-artifacts/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/linera-io/linera-artifacts/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/linera-io/linera-artifacts/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/linera-io/linera-artifacts/compare/v0.2.0...v0.2.2
[0.2.0]: https://github.com/linera-io/linera-artifacts/compare/v0.1.9...v0.2.0
[0.1.9]: https://github.com/linera-io/linera-artifacts/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/linera-io/linera-artifacts/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/linera-io/linera-artifacts/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/linera-io/linera-artifacts/compare/v0.1.3...v0.1.6
[0.1.3]: https://github.com/linera-io/linera-artifacts/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/linera-io/linera-artifacts/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/linera-io/linera-artifacts/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/linera-io/linera-artifacts/releases/tag/v0.1.0
