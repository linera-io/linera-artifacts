# Contributing to linera-io/linera-artifacts

Thanks for your interest in improving the public deployment artifacts for
Linera. This repository is small and focused: Helm charts, Docker images,
docker-compose files, and the documentation that goes with them.

## Issues

We use GitHub issues to track planned improvements, feature requests, and
bug reports.

- If you plan to contribute a new feature or chart, please open an issue
  first so we can discuss the approach.
- If you are reporting a bug, please include enough information to
  reproduce: chart version, values file, Kubernetes version, cluster
  provider, and what went wrong.

## Pull requests

1. Fork the repo and create your branch from `main`.
2. Make your changes in a focused commit (or a small series of focused commits).
3. Run the local checks listed below.
4. Open a pull request with a clear description of what changed and why.

This repository enforces a linear commit history. Use `git rebase` rather
than merge commits, and feel free to amend / force-push your PR branch
while it's under review.

Only commits in a PR that has been reviewed and approved should land on
`main`.

## Local checks

Before pushing, please run:

```bash
make lint test          # or: just lint test
make act                # or: just act — runs the full GitHub Actions workflow locally
```

The Makefile / Justfile exposes every check the CI runs (yamllint,
shellcheck, hadolint, helm lint, helm-unittest, kubeconform,
chart-testing, helm-docs drift). See `make help` / `just --list`.

CI will run the same checks on every push.

## Information leak — read before opening a PR

This is a **public** repo. Anything you commit (code, comments,
example values, screenshots, log snippets in PR descriptions) is
indexed by GitHub, mirrored by clones, and unrecoverable from search
caches even after a force-push. Specifically, do not commit or include in PR
discussions:

- Personal absolute paths (`/home/<your-username>/...`,
  `/Users/<your-username>/...`). Use `~`, `$PWD`, or relative paths.
- Internal hostnames, private DNS names, or production IP addresses
  (e.g. `*.infra.linera.net`, validator host IPs).
- Internal Slack / Discord channel names, internal ticket IDs that
  reference private repos, or names of teammates in commit
  messages.
- Real validator keys, real domain names you operate, real ACME
  emails. Use `validator.example.com` / `admin@example.com` /
  `your-domain.example.com` in every example.
- Internal-only image tags (`*_internal`). The public default is
  `testnet_conway_release`.
- Pasted output from running production validators (logs, metrics
  scrape, kubectl describe). Sanitize first or paraphrase.

If you find a leak in an existing file, treat it as a bug — open
a PR to scrub it (and assume it's already in the GitHub search
index). For credential / key leaks, also rotate immediately.

## Helm chart conventions

- Each chart lives under `helm/<name>/` with its own `Chart.yaml`,
  `values.yaml`, `README.md`, and `templates/`.
- Charts follow [SemVer](https://semver.org/). Bump `version` for any
  templated change; bump `appVersion` only when targeting a new
  upstream release.
- Default `values.yaml` should produce a working installation for a
  local cluster (kind / minikube). Cloud-specific overrides live under
  `docs/examples/`.
- Each value gets a `# --` comment line explaining what it does. This
  is what `helm-docs` picks up to regenerate `README.md`.

## Docker conventions

- Each image lives under `docker/<name>/` with its own `Dockerfile`,
  `entrypoint.sh`, and `README.md`.
- Pin upstream base images by digest, not by tag.
- Document required volumes, env vars, and exit codes in the
  image's `README.md`.

## Docs

User-facing docs live in `docs/`. Keep them practical:
each guide should be a working recipe a new operator can follow.

## License

By contributing, you agree that your contributions will be licensed
under the [Apache 2.0 license](LICENSE).
