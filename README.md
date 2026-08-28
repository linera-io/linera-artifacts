# <img src="https://github.com/linera-io/linera-protocol/assets/1105398/fe08c941-93af-4114-bb83-bcc0eaec95f9" width="250" height="85" />

[![License](https://img.shields.io/github/license/linera-io/linera-artifacts)](LICENSE)
[![Twitter](https://img.shields.io/twitter/follow/linera_io)](https://x.com/linera_io)
[![Discord](https://img.shields.io/discord/984941796272521226)](https://discord.com/invite/linera)
[![Docs](https://img.shields.io/badge/docs-validator-blue)](https://docs.infra.linera.net/)

Helm charts, a single-host Docker Compose stack, and operator scripts for
running a [Linera](https://github.com/linera-io/linera-protocol) validator.

**This repository is the source of truth for deploying a validator.**
linera-protocol is the protocol and binaries; the older
`scripts/deploy-validator.sh` it still carries is not the operator entry
point. Deploy from here.

## Repository layout

```
helm/                Charts published to ghcr.io/linera-io/charts
  linera-validator/        Core: shards + proxies
  linera-block-exporter/   Optional side-car (reads ScyllaDB → indexer)
  linera-validator-stack/  Umbrella: validator + ScyllaCluster CR
docker/              Single-host docker compose stack + observability overlays
scripts/             Bootstrap + lifecycle helpers
docs/                Operator guides + per-deployment example values
```

## Documentation

Operator-facing documentation is published at
**[docs.infra.linera.net](https://docs.infra.linera.net/)**
(installation guides, configuration reference, operations runbooks).
Sources live in [`docs/`](docs/) — edit there and PR; the site
rebuilds on merge to `main`.

[linera.dev](https://linera.dev) is the protocol / SDK reference for
developers building on Linera; it intentionally does not duplicate
the operator content here.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Issues and pull requests
welcome — please read the information-leak section before opening a
PR (this is a public repository).

## License

Apache 2.0. See [`LICENSE`](LICENSE).
