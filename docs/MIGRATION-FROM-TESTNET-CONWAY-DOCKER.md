# Migrating from `linera-protocol/docker` to `linera-io/linera-artifacts`

You're currently running a Linera validator from the `docker/`
directory inside `linera-protocol` (branch `testnet_conway`). This
guide moves you to the dedicated `linera-io/linera-artifacts` repository
without losing your ScyllaDB data or your validator key.

The two stacks are intentionally close so the cutover is shallow.
Read every step before you start — your validator goes offline for
the duration of the data copy (~5–10 min for a healthy host).

## What changes

| Aspect                       | Old: `linera-protocol/docker`               | New: `linera-io/linera-artifacts` `docker/`               |
|------------------------------|---------------------------------------------|----------------------------------------------------|
| Repo                         | `linera-protocol` @ `testnet_conway` branch | `linera-io/linera-artifacts` (single source-of-truth)     |
| Compose dir                  | `linera-protocol/docker/`                   | `linera-artifacts/docker/`                         |
| Helper script                | `scripts/deploy-validator.sh` in protocol   | `scripts/deploy-validator.sh` in artifacts (same name, simpler) |
| Persistence                  | **Named docker volumes** (`docker_linera-scylla-data`, etc.) | **Bind mounts** under `${SCYLLA_DATA_DIR:-./data/scylla}` etc. |
| Service shape                | `web`, `scylla`, `proxy`, `shard-0..3`, `shard-init`, `scylla-setup`, `watchtower` | **Same names, same container names** |
| Optional observability       | `docker-compose.alloy.yml` (push only)      | **Same name** — `docker-compose.alloy.yml` (push only) or `docker-compose.local-monitoring.yml` (heavy on-box stack) |
| `.env.production.template`   | Already there                                | Same file, plus a few new keys (data dirs, observability storage, alert tuning) |

Identical: the `LINERA_IMAGE`, the `validator-config.toml` format,
the `server.json` private key, the `genesis.json`, the Caddyfile,
the `scylla-setup.sh` host tuning script, the Watchtower auto-update
loop. **Reusable as-is** during the cutover.

## What does NOT carry over automatically

Two things to handle by hand:

1. **ScyllaDB data lives in a named docker volume in the old setup,
   in a bind-mounted host directory in the new one.** Re-using the
   data without re-syncing from genesis (which would take hours)
   means copying it via an ephemeral container — see Step 4 below.

2. **Caddy data (Let's Encrypt account + cert cache).** Same story:
   old `docker_caddy_data` / `docker_caddy_config` volumes → new
   bind mount. You can rebuild from scratch (Caddy will request a
   new cert) but reusing avoids hitting Let's Encrypt rate limits.

Wallet (`wallet.json`, `keystore.json`) — only present if you also
ran a Linera client on the same host. The validator itself never
needs them. Copy if you have them, skip if not.

## Step 0 — Prerequisites

You need:

- `docker` + the `docker compose` plugin (you already have these).
- ~30 GB of free disk space on the same filesystem where your
  ScyllaDB data lives, for the duration of the copy. Once the new
  stack is up and verified, the old volume can be deleted.
- ~15 minutes of validator downtime.

Tell the Linera network operators you're doing maintenance — they'll
exclude you from quorum calculations during the window.

## Step 1 — Inventory your current setup

Capture what you'll need to mirror, **without reading any secrets**:

```bash
cd ~/linera-protocol/docker            # or wherever your old setup lives
git rev-parse HEAD                     # for the record

ls -la genesis.json server.json validator-config.toml .env

# Volume names you'll migrate.
docker volume ls | grep -E "scylla|caddy"
```

Expected names: `docker_linera-scylla-data`, `docker_caddy_data`,
`docker_caddy_config` (the `docker_` prefix is the compose project
name, taken from the parent directory).

## Step 2 — Stop the old stack (keep volumes!)

```bash
cd ~/linera-protocol/docker
docker compose down                # NO -v — that would wipe Scylla
```

Sanity-check: the named volumes are still listed.

```bash
docker volume ls | grep -E "scylla|caddy"
```

## Step 3 — Clone the new repo

```bash
cd ~
git clone https://github.com/linera-io/linera-artifacts.git
cd linera-artifacts
```

## Step 4 — Copy the persistent data

The new stack expects:

- ScyllaDB data at `./docker/data/scylla/` (override with `SCYLLA_DATA_DIR`)
- Caddy data at `./docker/data/caddy-data/` (override with `CADDY_DATA_DIR`)
- Caddy config at `./docker/data/caddy-config/` (override with `CADDY_CONFIG_DIR`)

Spin up an ephemeral helper container that mounts both the old
named volume and the new bind-mount target, and copy. ScyllaDB is
the heavy one (likely tens of GB).

```bash
mkdir -p docker/data/scylla docker/data/caddy-data docker/data/caddy-config

# ScyllaDB — preserves ownership/permissions, important since the
# Scylla container runs as UID 999.
docker run --rm \
  -v docker_linera-scylla-data:/from \
  -v "$PWD/docker/data/scylla:/to" \
  alpine sh -c 'cd /from && tar cf - . | (cd /to && tar xf -)'

# Caddy data + config (small, fast).
docker run --rm \
  -v docker_caddy_data:/from -v "$PWD/docker/data/caddy-data:/to" \
  alpine sh -c 'cd /from && tar cf - . | (cd /to && tar xf -)'

docker run --rm \
  -v docker_caddy_config:/from -v "$PWD/docker/data/caddy-config:/to" \
  alpine sh -c 'cd /from && tar cf - . | (cd /to && tar xf -)'
```

Verify the Scylla data landed:

```bash
sudo du -sh docker/data/scylla
sudo ls docker/data/scylla | head      # should look like a Scylla data dir
                                        # (commitlog, data, hints, view_hints, …)
```

`sudo` because Scylla writes as UID 999.

## Step 5 — Carry over your validator identity + config

These are small files, just copy them:

```bash
cp ~/linera-protocol/docker/genesis.json          docker/
cp ~/linera-protocol/docker/server.json           docker/
cp ~/linera-protocol/docker/validator-config.toml docker/
cp ~/linera-protocol/docker/.env                  docker/
```

If you have a wallet on this host:

```bash
cp ~/linera-protocol/docker/wallet.json   docker/   # only if it exists
cp ~/linera-protocol/docker/keystore.json docker/   # only if it exists
cp -r ~/linera-protocol/docker/linera.db  docker/   # only if it exists
```

## Step 6 — Merge any new template variables into your `.env`

The new `.env.production.template` adds variables (data dirs,
observability storage, alert tuning) that didn't exist in the old
template. The helper script merges them safely without overwriting
your existing values:

```bash
./scripts/upgrade-env.sh
```

It writes a backup at `docker/.env.backup.YYYYMMDD-HHMMSS` and adds
the new variables commented out for you to review.

## Step 7 — Pick your observability setup

Two independent feature flags, can be combined:

| Flag                           | Adds                                                                | Old equivalent             |
|--------------------------------|---------------------------------------------------------------------|----------------------------|
| _(none — default)_             | Nothing extra. /metrics still on :21100.                            | No observability at all.   |
| `--with-alloy`                 | Alloy + cAdvisor push to remote OTLP endpoints in `.env`.           | `docker-compose.alloy.yml` |
| `--with-local-monitoring`      | Prometheus + Grafana + Loki + Tempo + alert rules on-box.           | `docker-compose.local-monitoring.yml` (rare) |
| Both flags                     | Push remote AND keep on-box dashboards.                             | n/a                        |

If you ran with `docker-compose.alloy.yml` before, use `--with-alloy`.
If you never ran observability, use no flags.

## Step 8 — Bring the new stack up

```bash
# Match whatever observability you had:
#   (no flag)                                  # default — no extra containers
#   --with-alloy                               # what you had if you used alloy.yml
#   --with-local-monitoring                    # heavy on-box stack
#   --with-alloy --with-local-monitoring       # both
./scripts/deploy-validator.sh --with-alloy \
  --skip-genesis \
  $YOUR_DOMAIN $YOUR_ACME_EMAIL
```

`--skip-genesis` because you already copied `genesis.json` in
Step 5; the script would otherwise re-download it. The validator's
`server.json` is also already there — the script detects that and
leaves your existing key untouched.

The first few seconds you'll see compose pulling the same images
you already had cached.

## Step 9 — Verify

```bash
cd docker
docker compose ps                     # all services Up
docker compose logs -f proxy          # proxy listening on 19100
```

Check that the validator is signing again — the network operators
should see your validator return to quorum within a couple of
minutes. Confirm with them before moving to the cleanup step.

## Step 10 — Decommission the old setup

Only when **everything is verified** for at least one full block
proposal cycle:

```bash
docker volume rm docker_linera-scylla-data docker_caddy_data docker_caddy_config

# Optional: drop the old protocol checkout. Keep `genesis.json` /
# `server.json` somewhere safe before deleting the directory.
# rm -rf ~/linera-protocol/docker
```

## What you can roll back to

If the new stack misbehaves, the old `linera-protocol/docker` setup
is still there until Step 10 is done. To roll back:

```bash
cd ~/linera-artifacts/docker
docker compose down                   # leave the bind-mount data alone

cd ~/linera-protocol/docker
docker compose up -d                  # back online with the original volume
```

Don't run both at once — they share container names and host ports.

## Once you're satisfied

The compose stack in `linera-protocol/docker` will be removed from
the protocol repo in a future release. This artifacts repo is the
canonical home going forward — pin your operations on it.

## Day-2 operations

Once migrated, every routine operation runs from `~/linera-artifacts/`.
The key thing to remember: **the same overlay flags you used at
deploy time must be passed every time you `docker compose up`**, or
your observability containers won't come back. The deploy script
records your choice in `.env` (as `DEPLOYMENT_*` metadata) but does
NOT replay it for you on subsequent compose commands — that's still
manual.

### Daily commands

```bash
cd ~/linera-artifacts/docker

# Check status
docker compose ps

# Tail logs (one service or all)
docker compose logs -f proxy
docker compose logs -f                    # all services

# Stop everything (no data loss)
docker compose -f docker-compose.yml \
               -f docker-compose.alloy.yml \
               down

# Bring it back up — same overlay set you used originally
docker compose -f docker-compose.yml \
               -f docker-compose.alloy.yml \
               up -d
```

If you used `--with-local-monitoring` at deploy time, also append
`-f docker-compose.local-monitoring.yml` to every compose command.
Both flags? Both files.

### Pulling a new linera image

Watchtower polls every 30s and rolls labelled containers when a new
image digest appears upstream — usually nothing for you to do. To
force the pull manually:

```bash
docker compose pull
docker compose up -d                      # picks up the new images
```

### Editing `.env` and re-applying

Most config changes only require a recreate of the affected service:

```bash
# After editing .env:
docker compose up -d                      # noop on unchanged services,
                                          # recreates the ones that changed
```

For changes that affect resource limits or volumes, restart the
specific container:

```bash
docker compose restart scylla             # in-place restart, same config
docker compose up -d --force-recreate scylla   # recreate from current .env
```

### Adding new env vars after a release

When the artifacts repo adds new variables to
`.env.production.template`, merge them into your existing `.env`
without losing your settings:

```bash
cd ~/linera-artifacts
git pull
./scripts/upgrade-env.sh                  # writes a backup; commented-out
                                          # new vars added for review
cd docker
docker compose up -d                      # apply
```

### Switching observability mode after the fact

Just bring the stack down with the **old** overlay set, then `up -d`
with the **new** one. State is bind-mounted so nothing is lost:

```bash
# Was: --with-alloy
docker compose -f docker-compose.yml -f docker-compose.alloy.yml down

# Now: --with-alloy AND --with-local-monitoring
docker compose -f docker-compose.yml \
               -f docker-compose.alloy.yml \
               -f docker-compose.local-monitoring.yml \
               up -d
```

### Backup

Everything important sits in bind-mounted directories under
`docker/data/` (Scylla) and `docker/{server,genesis,validator-config}.json`.
Snapshot or `rsync` the lot:

```bash
cd ~/linera-artifacts/docker
docker compose stop scylla                # consistent snapshot
sudo tar czf ~/validator-backup-$(date +%F).tgz \
  data/scylla server.json genesis.json validator-config.toml .env
docker compose start scylla
```

`server.json` is the only **irreplaceable** file — back it up
separately, encrypted, off-host.

### Full teardown (only if you know what you're doing)

```bash
cd ~/linera-artifacts/docker
docker compose -f docker-compose.yml \
               -f docker-compose.alloy.yml \
               down -v                    # -v wipes named volumes too
sudo rm -rf data/                         # wipes Scylla / Caddy data
# server.json + .env are NOT deleted — remove manually if rotating keys.
```
