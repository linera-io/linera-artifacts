# Linera Validator Artifacts

Everything you need to stand up, operate, and upgrade a Linera
validator: Helm charts, a single-host Docker Compose stack, deploy
scripts, and operator guides.

**This repository is the source of truth for deploying a validator.**
[linera-protocol](https://github.com/linera-io/linera-protocol) is the
protocol and binaries — build them there, deploy them from here. It also
contains an older `scripts/deploy-validator.sh` that predates this
repository and is not maintained as the operator entry point. If you
arrived from linera-protocol, run the script from *this* repository.

## Quickstart

Two supported paths — pick whichever matches your environment.

### One host (Docker Compose)

```bash
git clone https://github.com/linera-io/linera-artifacts.git
cd linera-artifacts
./scripts/deploy-validator.sh <hostname> <email>
```

That brings up a validator joining `testnet_conway`. See
[Quickstart](QUICKSTART.md) for details.

### Kubernetes (Helm)

Install from the OCI registry:

```bash
helm install validator-1 \
  oci://ghcr.io/linera-io/charts/linera-validator-stack \
  --version <version> \
  -f my-values.yaml
```

See [Helm guide](HELM.md).

## What's in this repo

| Directory   | What                                                     |
|-------------|----------------------------------------------------------|
| `helm/`     | Three Helm charts (`linera-validator`, `linera-block-exporter`, `linera-validator-stack` umbrella). |
| `docker/`   | Docker compose stack for single-host deployments.         |
| `scripts/`  | `deploy-validator.sh`, `upgrade-env.sh`, `install-prereqs.sh`. |
| `docs/`     | Operator guides (this site).                             |

## Security

Every release is signed with
[cosign keyless](https://docs.sigstore.dev/signing/overview) using
GitHub's OIDC. Verify before installing in production — see the
[Helm guide](HELM.md#verifying-signatures).

## Contributing

See [CONTRIBUTING](https://github.com/linera-io/linera-artifacts/blob/main/CONTRIBUTING.md).
