# Quickstart

The fastest path from zero to a running Linera validator joining an
existing network (testnet_conway today, mainnet when it's live).

Pick the flavor that matches your environment.

## Single host with Docker Compose

Best for most external validators: one dedicated VM or bare-metal
machine with Docker installed. Automatic TLS via Let's Encrypt,
auto-updates via Watchtower, host-level Scylla tuning all wired up.

### Prerequisites

- Hardware that meets the [recommended tier](HARDWARE.md) — 16-core /
  64 GB / NVMe SSD. Slower disks (HDD, network-attached storage) cause
  ScyllaDB to backpressure and OOM-kill the validator shards.
- Docker + docker compose plugin
- A public DNS name pointing at this host (for Let's Encrypt)
- Ports 80 and 443 reachable from the internet

### Deploy

```bash
git clone https://github.com/linera-io/linera-artifacts.git
cd linera-artifacts

./scripts/deploy-validator.sh validator.example.com admin@example.com
```

That one command:

1. Downloads the current network's `genesis.json` from the public Linera GCS bucket
2. Generates a `validator-config.toml` matching the compose topology
3. Generates your `server.json` (private signing key — **never share**)
4. Writes `docker/.env` from `.env.production.template` **with your values
   filled in** — `DOMAIN`, `ACME_EMAIL`, `GENESIS_URL`, `GENESIS_BUCKET`,
   `GENESIS_PATH_PREFIX`, `VALIDATOR_KEY`, `VALIDATOR_NAME`, `HOSTNAME`,
   `LINERA_VALIDATOR_IMAGE`, `LINERA_CLIENT_IMAGE` and `NUM_SHARDS`. It does not just copy the template; you
   do not need to edit the result before starting.
5. Brings the whole stack up

At the end it prints your **public key**. Send it to the Linera network
operators to register your validator.

### What you actually have to provide

The template lists a lot of variables, but almost all of them are commented
out and already carry the value the stack uses, so a working deployment
needs very little from you:

- **Two variables** — `DOMAIN` and `ACME_EMAIL`. Caddy needs them for the
  Let's Encrypt certificate; without a valid one the validator is not
  reachable by the rest of the network.
- **Two files** — `server.json` and `genesis.json`, in `docker/`. That
  directory is bind-mounted at `/config`, so the containers read both from
  disk rather than through `.env`.

`deploy-validator.sh` produces all four for you. Everything else in the
template is tuning: see the
[Docker Compose reference](DOCKER-COMPOSE.md#configuration-via-env), and
note that the storage/cache and ScyllaDB commitlog defaults are already the
values the testnet-conway validators run in production.

Watch the rollout:

```bash
cd docker
docker compose logs -f proxy
```

### Upgrading

When a new release adds configuration variables, merge them in safely:

```bash
./scripts/upgrade-env.sh
cd docker && docker compose up -d
```

This preserves every value you had set, appends any new variables
(commented out for you to review), and backs up the old `.env` first.

Full reference: [`docs/DOCKER-COMPOSE.md`](DOCKER-COMPOSE.md).

## Kubernetes

For operators who already run a Kubernetes fleet and want to manage
validators with ArgoCD / Flux / plain Helm.

Prerequisites:

- Kubernetes 1.27+
- Helm 3.8+ (for OCI registry support)
- [scylla-operator](https://github.com/scylladb/scylla-operator) installed

```bash
# 1. Create the secret with the per-validator signing key and genesis.
#    Obtain these from the Linera network operators.
kubectl create namespace linera
kubectl --namespace linera create secret generic validator-config \
  --from-file=serverConfig=./server.json \
  --from-file=genesisConfig=./genesis.json

# 2. Install the umbrella chart.
helm install validator-1 \
  oci://ghcr.io/linera-io/charts/linera-validator-stack \
  --namespace linera \
  --set linera-validator.image.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-validator \
  --set linera-validator.image.tag=testnet_conway_release \
  --set linera-validator.clientImage.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-client \
  --set linera-validator.clientImage.tag=testnet_conway_release \
  --set linera-validator.validator.existingSecret=validator-config
```

Watch the rollout:

```bash
kubectl --namespace linera get pods -w
```

Smoke-test once pods are `Ready`:

```bash
helm test validator-1 --namespace linera
```

Full reference: [`docs/HELM.md`](HELM.md).

## Standalone validator chart (no umbrella)

Skip the umbrella when you already manage ScyllaDB separately:

```bash
helm install validator-1 \
  oci://ghcr.io/linera-io/charts/linera-validator \
  --namespace linera \
  --set image.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-validator \
  --set image.tag=testnet_conway_release \
  --set clientImage.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-client \
  --set clientImage.tag=testnet_conway_release \
  --set storage.uri='scylladb:tcp:my-scylla.svc:9042' \
  --set validator.existingSecret=validator-config
```

See the [`linera-validator` chart README](https://github.com/linera-io/linera-artifacts/tree/main/helm/linera-validator)
for the full value reference.

## Where next

- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — what gets deployed and why
- [`docs/POST-SETUP.md`](POST-SETUP.md) — day-2 operations: logs, restarts, backup, env upgrades
- [`docs/examples/`](examples/README.md) — values files for common K8s scenarios
