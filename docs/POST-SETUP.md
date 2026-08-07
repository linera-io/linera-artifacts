# Post-setup operations

Day-to-day operating commands for a running validator. Everything here
runs from `~/linera-artifacts/`.

The key thing to remember: **the same overlay flags you used at deploy
time must be passed every time you `docker compose up`**, or your
observability containers won't come back. The deploy script records
your choice in `.env` (as `DEPLOYMENT_*` metadata) but does NOT replay
it for you on subsequent compose commands — that's still manual.

## Daily commands

```bash
cd ~/linera-artifacts/docker

# Check status
docker compose ps

# Tail logs (one service or all)
docker compose logs -f proxy
docker compose logs -f                    # all services

# Stop everything (no data loss)
docker compose -f docker-compose.yaml \
               -f docker-compose.alloy.yaml \
               down

# Bring it back up — same overlay set you used originally
docker compose -f docker-compose.yaml \
               -f docker-compose.alloy.yaml \
               up -d
```

If you used `--with-local-monitoring` at deploy time, also append
`-f docker-compose.local-monitoring.yaml` to every compose command.
Both flags? Both files.

## Pulling a new linera image

Watchtower polls every 30s and rolls labelled containers when a new
image digest appears upstream — usually nothing for you to do. To
force the pull manually:

```bash
docker compose pull
docker compose up -d                      # picks up the new images
```

## Editing `.env` and re-applying

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

## Adding new env vars after a release

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

## Switching observability mode after the fact

Just bring the stack down with the **old** overlay set, then `up -d`
with the **new** one. State is bind-mounted so nothing is lost:

```bash
# Was: --with-alloy
docker compose -f docker-compose.yaml -f docker-compose.alloy.yaml down

# Now: --with-alloy AND --with-local-monitoring
docker compose -f docker-compose.yaml \
               -f docker-compose.alloy.yaml \
               -f docker-compose.local-monitoring.yaml \
               up -d
```

## Backup

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

## Full teardown (only if you know what you're doing)

```bash
cd ~/linera-artifacts/docker
docker compose -f docker-compose.yaml \
               -f docker-compose.alloy.yaml \
               down -v                    # -v wipes named volumes too
sudo rm -rf data/                         # wipes Scylla / Caddy data
# server.json + .env are NOT deleted — remove manually if rotating keys.
```
