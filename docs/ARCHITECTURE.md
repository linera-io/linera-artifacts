# Architecture

What the `linera-io/linera-artifacts` charts deploy and how the pieces fit
together.

## A Linera validator at a glance

A validator is the smallest unit that participates in network
consensus. Each validator runs:

- **N shard processes** — process operations on Linera microchains.
  Each shard owns a deterministic subset of all chains. Shards are
  stateless: all persistence happens in the storage backend.
- **1+ proxy processes** — accept gRPC traffic from clients (wallets,
  dApps) and route it to the right shard. Multiple proxies form an
  HA group.
- **A storage backend** — ScyllaDB in production. Holds chain state
  and the consensus log.

Validators are independent. There is no leader; consensus is reached
by Byzantine-fault-tolerant agreement among the committee defined in
`genesis.json`.

```
                        ┌──────────────────────────┐
   wallet / dApp ──gRPC─┤  proxy (StatefulSet)     │
                        └────────────┬─────────────┘
                                     │ shards-by-chain hashing
                       ┌─────────────┼──────────────┐
                       ▼             ▼              ▼
                  ┌────────┐    ┌────────┐    ┌────────┐
                  │shard-0 │    │shard-1 │    │shard-N │  shards (StatefulSet)
                  └────┬───┘    └────┬───┘    └────┬───┘
                       └─────────────┴──────────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │   ScyllaDB      │  storage backend
                            └─────────────────┘
```

## Charts in this repo

```
linera-validator-stack          (umbrella)
├── linera-validator            (always; shards + proxies)
└── linera-block-exporter       (optional; always-on side-car that
                                 re-publishes blocks to the network)
+ ScyllaCluster CR              (storage backend)
+ scylla-config ConfigMap       (scylla.yaml)
```

### linera-validator

Two `StatefulSet`s plus the Services that front them:

- `<release>-shards` — N replicas, headless Service (gRPC peering).
- `<release>-proxy` — M replicas, one external Service for clients
  and one headless internal Service for proxy↔proxy traffic.

Both pods read the same `Secret` (genesis + signing key) at startup.
The signing key is **never** baked into the image and **never** stored
as a `ConfigMap` — only as a `Secret`, by design.

Each container's command is built dynamically from a values map so
operators can tune `--storage-max-cache-size` etc. without forking
the chart. The defaults match the testnet-conway production values.

### linera-block-exporter

Optional, always-on side-car that every validator **can** choose to
run to help the rest of the network.

A separate `StatefulSet` that subscribes to its own validator's
storage, serializes new blocks, and pushes them over gRPC to the
other validators so they can catch up faster when they fall behind.
It keeps running for the life of the release — the opt-in decision
is whether to turn it on, not when to start/stop it.

One TOML config file is generated per replica (keyed by ordinal);
multiple replicas shard the work between them via the `id` field.

It must run in the same cluster as the validator and connect to the
same ScyllaDB. It cannot be operated standalone.

### linera-validator-stack

Umbrella that bundles the two charts above plus a `ScyllaCluster`
custom resource. It does **not** install operators (scylla-operator,
cert-manager) — those are pre-requisites the cluster must already
satisfy.

## Public exposure

The proxy is the only component that should be reachable from outside
the cluster. The chart supports two patterns:

- `gateway.enabled=true` — **recommended.** Emit a Gateway API
  `Gateway` + `GRPCRoute`. Preserves HTTP/2 to the proxy and works
  cleanly with cert-manager + external-dns. This is the path the
  Kubernetes project now recommends for new deployments — see the
  [official note on the Ingress page](https://kubernetes.io/docs/concepts/services-networking/ingress/).
- `ingress.enabled=true` — **deprecated / maintenance mode.** Emit a
  `networking.k8s.io/v1` `Ingress`. The Ingress API is feature-frozen
  upstream; kept here as a compatibility path for clusters that only
  ship an Ingress controller (nginx, gce, etc.).

Enable one, not both.

## Storage

ScyllaDB is the canonical storage backend in production. The chart
defaults `storage.uri` to
`scylladb:tcp:scylla-client.scylla.svc.cluster.local:9042` — what the
umbrella chart provisions.

For local development the validator chart also supports
`storage.dual=true` which adds a per-shard `RocksDB` PVC alongside
ScyllaDB writes. The compose stack uses ScyllaDB only.

## Observability

The chart emits `ServiceMonitor` resources (when `serviceMonitor.enabled=true`)
for every shard, proxy, and exporter. They expose `/metrics` on a
dedicated port that's separate from the gRPC traffic.

The chart does **not** install Prometheus, Grafana, Loki, or Tempo —
those are deliberately out of scope. Operators run them separately and
point them at the validator namespace.
