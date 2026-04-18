# Chart development loop

For contributors iterating on the Helm charts in this repo. Two
complementary flavours:

- **DevSpace** — fast inner loop: kind cluster stays up, `helm
  upgrade` on every save, port-forward + live logs. Best while you
  edit templates / values and want feedback in seconds.
- **chart-testing (`ct install`)** — CI-grade validation: spin up a
  throw-away kind cluster, install every chart, run `helm test`,
  tear down. Best as a pre-commit sanity check — matches what GitHub
  Actions runs on your PR.

This document is about **chart iteration only**. It is not a
protocol-development workflow — if you're iterating on the `linera`
binary itself, that belongs in `linera-protocol`.

---

## Option A — DevSpace (inner loop)

### Prerequisites

Install once (or `direnv allow` the nix devshell — it provides all
of these):

- [Docker](https://docs.docker.com/engine/install/)
- [kind](https://kind.sigs.k8s.io/)
- [DevSpace CLI](https://www.devspace.sh/docs/getting-started/installation)
- `helm` 3.8+ and `kubectl`

### Quickstart

```bash
git clone https://github.com/linera-io/linera-artifacts.git
cd linera-artifacts

just dev      # or: make dev
```

The `dev` target:

1. Creates a local kind cluster called `linera-dev` (idempotent) and
   points `kubectl` at it.
2. Pre-creates the `linera` and `scylla` namespaces.
3. Hands off to `devspace dev --namespace linera`, which:
   a. Runs `scripts/install-prereqs.sh --install-cert-manager` to
      install cert-manager + scylla-operator.
   b. Generates a placeholder `server.json` + the public testnet
      `genesis.json` and wraps them in the `validator-config`
      secret.
   c. Installs `linera-validator-stack` with developer-sized
      resources (1 shard, 1 proxy, Scylla at 10Gi, observability
      off).
   d. Port-forwards the proxy to `localhost:19100` and streams its
      logs.

Save any file under `helm/` and DevSpace re-runs `helm upgrade`
automatically.

The placeholder signing key is **not** part of the testnet committee,
so shards start and expose metrics but don't produce accepted
blocks. That is the expected state for chart work — it exercises
every template, RBAC, service, and mount without needing network
operator coordination.

### Detaching

`just dev` stays attached for log streaming and port-forwarding.
**Ctrl+C is safe** — it only stops those two things; the chart and
the kind cluster keep running. Reattach any time:

```bash
kubectl --context kind-linera-dev -n linera logs -f \
  -l app.kubernetes.io/component=proxy

kubectl --context kind-linera-dev -n linera port-forward \
  svc/validator-proxy 19100:19100
```

Or use the fully detached wrapper:

```bash
just dev-bg          # devspace deploy + nohup kubectl port-forward
just dev-bg-stop     # stop the port-forward
just dev-down        # full teardown (chart + kind cluster)
```

### Direct `devspace` usage

`just dev` / `make dev` is the suggested entrypoint because it
creates the kind cluster and switches the kube context for you.
DevSpace v6 (config schema `v2beta1`) has no top-level `kubeContext`
field — pinning is CLI/env only — so the wrapper saves you a
manual `kubectl config use-context`. Direct `devspace dev` works
fine once you've got the context active:

```bash
kubectl config use-context kind-linera-dev
devspace dev
```

### Caveats

- Kind + ScyllaDB is resource-hungry: leave at least 4 CPU cores and
  6 GB of RAM free on the host.
- `.devspace/network-config/` holds generated config (placeholder
  server.json, downloaded genesis.json). It's `.gitignored` — safe
  to delete and rerun.
- Plain `devspace purge` only removes the chart; it keeps the kind
  cluster around on purpose so you can iterate. Use `just dev-down`
  for a full teardown.

---

## Option B — chart-testing (`ct install`)

Runs the same checks GitHub Actions does: `ct lint` (validates
`Chart.yaml` metadata, version bumps, dependency declarations) plus
optionally `ct install` (creates a fresh kind cluster, installs
every changed chart, runs `helm test`, tears down).

```bash
just ct-lint             # what CI runs on every PR
just ct-install          # full install-and-test in kind
```

Use this before opening a PR, or when you've changed `Chart.yaml`
metadata. It takes longer than the DevSpace loop (full kind spin-up
per run) and doesn't keep anything around for exploration, but it
gives you the same PASS/FAIL signal CI will.

---

## Which one to use

| You're doing… | Reach for |
|---|---|
| Tweaking a template, want to see the rendered manifest in a live cluster | DevSpace |
| Adjusting resource defaults, scheduling, probes | DevSpace |
| About to open a PR, want CI-equivalent green | `just ct-lint` |
| Bumped a chart version / added a dependency / changed maintainers | `just ct-install` |
| Debugging why a pod won't start | DevSpace (port-forward + live logs) |

Both reuse the same `helm/linera-validator-stack/` chart that ships
to operators — no dev-only shim.
