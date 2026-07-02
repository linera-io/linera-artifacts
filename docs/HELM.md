# Helm reference

How to install, configure, and operate the Linera Helm charts. For
chart-by-chart value documentation see each chart's own README.

## Where the charts live

All charts are published to GitHub Container Registry as OCI artifacts:

| Chart                     | OCI reference                                               |
|---------------------------|-------------------------------------------------------------|
| `linera-validator`        | `oci://ghcr.io/linera-io/charts/linera-validator`           |
| `linera-block-exporter`   | `oci://ghcr.io/linera-io/charts/linera-block-exporter`      |
| `linera-validator-stack`  | `oci://ghcr.io/linera-io/charts/linera-validator-stack`     |

Helm 3.8+ is required for OCI registry support.

## Prerequisites

The validator chart needs a reachable ScyllaDB. The **umbrella chart**
(`linera-validator-stack`) provisions one via a `ScyllaCluster` custom
resource but requires **scylla-operator** to be installed first.

Install it with the helper script:

```bash
# scylla-operator only — assumes cert-manager is already installed
# in the cluster (scylla-operator's helm chart references
# cert-manager.io/v1 Certificate + Issuer CRDs at render time).
./scripts/install-prereqs.sh

# scylla-operator + cert-manager (one-shot for fresh clusters).
./scripts/install-prereqs.sh --install-cert-manager
```

The script is idempotent — re-run it to upgrade the operators in
place. When `--install-cert-manager` is passed, cert-manager is
installed **before** scylla-operator so its CRDs are available.

`external-dns` (for DNS record management) is recommended for
production Gateway API installs but out of scope for this helper
script — install it however you normally manage cluster-wide
infrastructure.

## Installing

```bash
helm install <release> <oci-ref> \
  --version <chart-version> \
  --namespace <ns> --create-namespace \
  -f my-values.yaml
```

Pin `--version` explicitly. The chart version follows SemVer; the
`appVersion` baked into each chart matches the supported `linera`
binary release. Bumping the chart minor while keeping appVersion
constant is allowed; bumping appVersion always bumps the chart's
patch.

### Choosing a chart

| You want…                                              | Install                        |
|--------------------------------------------------------|--------------------------------|
| Just the validator workload (supply your own ScyllaDB) | `linera-validator`             |
| Validator + managed ScyllaCluster in one release       | `linera-validator-stack`       |
| Add an always-on block exporter to help the network    | `linera-block-exporter`        |

## Required values

Every install needs:

| Value                                | Description                                                      |
|---------------------------------------|------------------------------------------------------------------|
| `image.repository` + `image.tag`     | Linera binary image (or set `image.tag` from `appVersion`).      |
| `validator.existingSecret`           | Secret with `serverConfig` + `genesisConfig` keys.               |
| `storage.uri`                        | ScyllaDB connection string.                                      |

Generate the secret with:

```bash
kubectl create secret generic validator-config \
  --from-file=serverConfig=server_1.json \
  --from-file=genesisConfig=genesis.json
```

Obtain the `server.json` (per-validator, private signing key) and the
network's `genesis.json` (public) from the Linera network operators.

## Common patterns

### Exposing the proxy

Pick **one**. The validator proxy speaks gRPC over HTTP/2.

**Recommended — Gateway API:**

```yaml
gateway:
  enabled: true
  className: envoy
  hostname: validator.example.com
  tlsSecretName: validator-tls
```

The Kubernetes project has placed the Ingress API in feature freeze
and recommends Gateway API for new deployments. See the official
note at the top of the [Ingress documentation
page](https://kubernetes.io/docs/concepts/services-networking/ingress/)
and the [Gateway API project](https://gateway-api.sigs.k8s.io/).
Gateway API also handles gRPC more cleanly than Ingress controllers
historically have.

**Legacy — Ingress (maintenance mode, use only if your cluster has
no Gateway API implementation):**

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: validator.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: validator-tls
      hosts: [validator.example.com]
```

!!! warning "Ingress is frozen"
    The Ingress API is no longer receiving new features. Treat this
    block as a compatibility path for clusters that only ship an
    Ingress controller. New installs should use the `gateway` block
    above.

### Resource sizing

The chart ships conservative defaults that boot cleanly on a small
cluster (kind, a couple of small nodes) so operators can validate
the install before sizing it up. Production sizing depends on your
hardware (vCPU per node, memory per node), the network's shard
count, and observed load — there is no single "production values"
snippet that fits every operator.

Shape of what you override:

```yaml
shards:
  replicas: <N>
  resources:
    requests: { cpu: "<cpu>", memory: "<mem>" }
    limits:   { cpu: "<cpu>", memory: "<mem>" }

proxies:
  replicas: <N>
  resources:
    requests: { cpu: "<cpu>", memory: "<mem>" }
    limits:   { cpu: "<cpu>", memory: "<mem>" }
```

Rules of thumb:

- **Shard replica count** is fixed by the network (protocol
  parameter). Match it; don't pick arbitrarily.
- **Shard memory** dominates — shards cache chain state. Size
  requests close to limits; OOM-killed shards disrupt the validator.
- **Proxies are CPU/network-bound**, not memory-bound.
- **One shard per node** is a common pattern for predictable tail
  latency. Use `topologySpreadConstraints` + `nodeSelector` to
  enforce it (see next section).
- Ask the Linera network operators for the current recommended
  floor for the network you're joining — recommendations change as
  load evolves.

### Pinning to specific nodes

Shards and proxies each accept `nodeSelector`, `tolerations`,
`affinity`, and `topologySpreadConstraints`:

```yaml
shards:
  nodeSelector:
    node-pool: validator-shards
  tolerations:
    - key: linera.io/dedicated
      value: shards
      effect: NoSchedule
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app.kubernetes.io/component: shards
```

### ScyllaDB performance (production)

The `linera-validator-stack` umbrella provisions a `ScyllaCluster` from
`scylla.*` values. The defaults boot on a small cluster, but ScyllaDB is
latency-critical for a validator and needs deliberate tuning to match the
production (GKE) validators.

#### Fast SSD storage class — do not skip this

`scylla.rack.storage.storageClassName` defaults to `""` (the cluster's
**default** StorageClass). For ScyllaDB that is almost never what you want:
the default class is frequently HDD- or network-backed and will not meet
Scylla's I/O requirements, producing read-latency spikes that stall block
production. **Set this explicitly to a fast SSD class.** Recommended per
provider:

| Provider | StorageClass | Notes |
|----------|-------------|-------|
| GKE, regional PD-SSD | `premium-rwo` | Good default. |
| GKE, zonal local NVMe (fastest) | `local-ssd-resource-adapter` | Needs the Local SSD CSI driver enabled and a nodepool with `--local-ssd-count > 0`. |
| EKS, gp3 SSD | `gp3` | |
| AKS, Premium SSD v2 | `managed-premium` | |
| OVH, managed control-plane SSD | `csi-cinder-high-speed` | |
| Bare metal, local NVMe | `local-path` (Rancher) or a custom provisioner | |

If you only have HDD-backed storage, you will not meet Scylla's I/O floor —
run Scylla on a bare-metal host with a local NVMe instead.

#### Durable commitlog (default)

`scylla.config.commitlogSync` defaults to `batch` with
`commitlogSyncBatchWindowMs: 2`, which fsyncs each write batch (matching the
production validators) instead of flushing periodically (~10s, which loses
recent writes on a crash). Override `commitlogSync: periodic` (or `""` to use
Scylla's own default) only if you understand the durability trade-off. This
takes effect on a Scylla pod restart.

#### Core pinning + IRQ steering (the three-part requirement)

For GKE-equivalent tail latency, Scylla must own its CPU cores and keep NIC
interrupts off them. That requires **all three** of the following together —
any one alone does nothing:

1. **A dedicated Scylla nodepool.** Taint it and pin the rack to it via
   `scylla.rack.placement.nodeAffinity` + `scylla.rack.placement.tolerations`
   so no other workload shares those cores.
2. **`cpuManagerPolicy=static` on that nodepool's kubelet.** This is a
   nodepool/kubelet setting (e.g. set it in your GKE/EKS nodepool config or
   kubelet flags), not a chart value. It lets the static CPU manager grant
   Scylla's container exclusive integer cores — which in turn requires the pod
   to be **Guaranteed QoS**. The chart already arranges Guaranteed QoS by
   giving the agent sidecar `scylla.rack.agentResources` with
   `requests==limits` (fractional, so the agent stays off Scylla's cores).
3. **The tuning NodeConfig.** Set `scylla.tuning.enabled=true` to emit a
   `scylla.scylladb.com/v1alpha1` `NodeConfig` that tells scylla-operator to
   run `perftune` on the selected nodes: pin Scylla to its cores, steer NIC
   IRQs off those cores, and apply kernel/net/disk-scheduler sysctls. Point
   `scylla.tuning.nodeSelector` / `scylla.tuning.tolerations` at the same
   dedicated nodepool. It is **disabled by default** because on a shared,
   non-statically-pinned nodepool it provides no benefit.

```yaml
scylla:
  rack:
    storage:
      storageClassName: premium-rwo
    placement:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - { key: workload, operator: In, values: [scylla] }
      tolerations:
        - { key: scylla-db, operator: Equal, value: "true", effect: NoSchedule }
  tuning:
    enabled: true
    nodeSelector: { workload: scylla }
    tolerations:
      - { key: scylla-db, operator: Equal, value: "true", effect: NoSchedule }
```

### Observability

The charts emit `ServiceMonitor` resources (when
`serviceMonitor.enabled=true`) for every shard, proxy, and exporter.
Make sure your Prometheus selects them — most operators look for a
release label:

```yaml
serviceMonitor:
  enabled: true
  labels:
    release: prometheus
```

The charts do **not** install Prometheus, Grafana, Loki, or Tempo.

## Smoke testing after install

```bash
helm test <release> --namespace <ns>
```

Each chart ships a `helm.sh/hook: test` pod that probes the primary
endpoint (TCP for the validator proxy and the block-exporter metrics)
and exits non-zero if it can't connect within a short timeout.

## Upgrading

```bash
helm upgrade <release> <oci-ref> \
  --version <new-version> \
  --namespace <ns> \
  --reuse-values
```

Compatibility:

- Major chart versions can break value layout. Read the changelog.
- Chart minor versions are backwards-compatible for values.
- `appVersion` bumps may require a new `genesis.json` if the on-wire
  protocol changed; consult the linera-protocol release notes.

## Uninstalling

```bash
helm uninstall <release> --namespace <ns>
```

This removes the chart-managed resources but **does not** delete:

- PersistentVolumeClaims (for `storage.dual` or block-exporter persistence)
- The Secret you supplied via `validator.existingSecret`
- ScyllaDB data or PostgreSQL data

Clean those up explicitly when you really mean to wipe state.

## Verifying signatures

Charts are signed with cosign keyless. Verify before installing in
production:

```bash
cosign verify oci://ghcr.io/linera-io/charts/linera-validator:<version> \
  --certificate-identity-regexp 'https://github.com/linera-io/linera-artifacts/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
