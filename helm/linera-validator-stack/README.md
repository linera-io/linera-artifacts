# linera-validator-stack

![Version: 0.1.5](https://img.shields.io/badge/Version-0.1.5-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.13.0](https://img.shields.io/badge/AppVersion-0.13.0-informational?style=flat-square)

Umbrella chart that installs everything needed to run a Linera
validator in one shot: the validator (shards + proxies), an optional
block exporter, and a ScyllaCluster CR for the storage backend.

The chart depends on linera-validator and linera-block-exporter from
this same repository. Each sub-chart is opt-in via its
`<name>.enabled` value (validator on by default; the block exporter
off).

Prerequisite operators that must already be installed in the cluster:
  - scylla-operator   (for the ScyllaCluster CR)

**Homepage:** <https://linera.io>

Use this chart for the simplest possible single-namespace setup. For
production-grade installs that want components in separate releases /
namespaces, install the sub-charts individually.

## Sub-charts

| Sub-chart | Default | Description |
|-----------|---------|-------------|
| [`linera-validator`](../linera-validator/) | enabled | Validator core (shards + proxies). |
| [`linera-block-exporter`](../linera-block-exporter/) | disabled | Side-car that pushes blocks to indexers. |

## Bundled resources

The umbrella also emits:

- A `ScyllaCluster` CR (requires
  [scylla-operator](https://github.com/scylladb/scylla-operator) to be
  pre-installed).
- The `scylla-config` ConfigMap consumed by the ScyllaCluster as its
  `scylla.yaml`.

## Prerequisites

The umbrella **does not install operators**. The following must
already exist in the cluster:

- [scylla-operator](https://github.com/scylladb/scylla-operator)
  (always required when `scylla.enabled=true`)
- cert-manager and external-dns are recommended for production but
  optional.

## TL;DR

```bash
helm install validator-1 \
  oci://ghcr.io/linera-io/charts/linera-validator-stack \
  --namespace linera --create-namespace \
  --set linera-validator.image.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera \
  --set linera-validator.image.tag=testnet_conway_release \
  --set linera-validator.validator.existingSecret=validator-config
```

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Linera infrastructure team |  | <https://github.com/linera-io> |

## Source Code

* <https://github.com/linera-io/linera-artifacts>
* <https://github.com/linera-io/linera-protocol>

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://../linera-block-exporter | linera-block-exporter | 0.1.3 |
| file://../linera-validator | linera-validator | 0.1.4 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| linera-block-exporter | object | `{"destinations":[],"enabled":false,"storage":{"uri":"scylladb:tcp:scylla-client.scylla.svc.cluster.local:9042"}}` | --------------------------------------------------------------------------- |
| linera-validator.enabled | bool | `true` |  |
| scylla | object | `{"agentImage":"scylladb/scylla-manager-agent","agentVersion":"3.4.0@sha256:441403aed8880cad1feef68aa7a8ee9ffd99a458dc1dcff3dc54ce5bf3cb07b7","backups":{"cron":"0 4 * * *","enabled":false,"keyspaces":["kv"],"location":"","name":"daily-backup","numRetries":3,"rateLimit":["50"],"retentionDays":90},"config":{"commitlogSync":"batch","commitlogSyncBatchWindowMs":2,"create":true,"data":{"commitlog_segment_size_in_mb":64,"query_tombstone_page_limit":200000}},"datacenter":"validator","developerMode":false,"enabled":true,"name":"scylla","namespace":"scylla","rack":{"agentResources":{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"200m","memory":"256Mi"}},"members":1,"name":"rack","placement":{"nodeAffinity":{},"tolerations":[]},"resources":{"limits":{"cpu":"7","memory":"51Gi"},"requests":{"cpu":"7","memory":"51Gi"}},"storage":{"capacity":"1000Gi","storageClassName":""}},"scyllaImage":"scylladb/scylla","scyllaVersion":"6.2.3","sysctls":["fs.aio-max-nr=4082080"],"tuning":{"enabled":false,"name":"scylla-tuning","nodeSelector":{"workload":"scylla"},"tolerations":[{"effect":"NoSchedule","key":"scylla-db","operator":"Equal","value":"true"}]}}` | --------------------------------------------------------------------------- Requires scylla-operator to be installed in the cluster (CRDs). Set scylla.enabled=false to bring your own storage backend. |
| scylla.backups | object | `{"cron":"0 4 * * *","enabled":false,"keyspaces":["kv"],"location":"","name":"daily-backup","numRetries":3,"rateLimit":["50"],"retentionDays":90}` | Backup schedule (Scylla Manager). Set to {} to disable. |
| scylla.config | object | `{"commitlogSync":"batch","commitlogSyncBatchWindowMs":2,"create":true,"data":{"commitlog_segment_size_in_mb":64,"query_tombstone_page_limit":200000}}` | ConfigMap consumed by the ScyllaCluster as its scylla.yaml. Created in the same namespace as the cluster. |
| scylla.config.commitlogSync | string | `"batch"` | Commitlog durability mode. "batch" fsyncs each write batch (durable, production default, promoted fleet-wide from the testnet-conway canary); "periodic" flushes on a timer (~10s, faster but loses recent writes on a crash). Set to "" to omit the key and use Scylla's own default. |
| scylla.config.commitlogSyncBatchWindowMs | int | `2` | When commitlogSync is "batch", how long (ms) Scylla waits to coalesce other writes before fsync. Only rendered when commitlogSync == "batch". |
| scylla.datacenter | string | `"validator"` | Datacenter name (informational, exposed as a Scylla DC label). |
| scylla.developerMode | bool | `false` | Enable ScyllaCluster developerMode. Skips strict cpuset/CPU pinning, fewer resource checks. NEVER set true in production — only useful for kind / minikube / single-node test clusters. |
| scylla.name | string | `"scylla"` | ScyllaCluster name. Used by the auto-generated client Service (scylla-client.<namespace>.svc.cluster.local). |
| scylla.namespace | string | `"scylla"` | Namespace where the ScyllaCluster lives. The chart does NOT create this namespace — create it ahead of time or let scylla-operator do it. |
| scylla.rack | object | `{"agentResources":{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"200m","memory":"256Mi"}},"members":1,"name":"rack","placement":{"nodeAffinity":{},"tolerations":[]},"resources":{"limits":{"cpu":"7","memory":"51Gi"},"requests":{"cpu":"7","memory":"51Gi"}},"storage":{"capacity":"1000Gi","storageClassName":""}}` | One ScyllaCluster rack. Add more entries to spread across racks. |
| scylla.rack.agentResources | object | `{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"200m","memory":"256Mi"}}` | Resources for the scylla-manager-agent sidecar. Set requests==limits (and put them on EVERY container in the pod, as the integer-cpu `resources` above already does) so the whole pod lands in the Guaranteed QoS class. Guaranteed QoS is what lets the kubelet static CPU manager hand Scylla's container its integer CPUs as EXCLUSIVE cores — which the optional `scylla.tuning` NodeConfig then pins and IRQ-steers around.  Kept FRACTIONAL (200m) on purpose: the agent stays in the shared CPU pool instead of consuming one of Scylla's dedicated cores. 256Mi is a deliberate floor — the scylla-operator default of 10M memory would OOM the agent on its first backup upload once limits are enforced. |
| scylla.rack.storage.storageClassName | string | `""` | StorageClass for the Scylla PVCs. Empty = cluster default (rarely what you want for ScyllaDB).  Recommended values by provider:   GKE, regional PD-SSD:                   "premium-rwo"   GKE, zonal local SSDs (NVMe, fastest): "local-ssd-resource-adapter"                                          (requires the Local SSD CSI                                          driver enabled on the cluster                                          and matching nodepool with                                          --local-ssd-count > 0)   EKS, gp3 SSD:                          "gp3"   AKS, Premium SSD v2:                   "managed-premium"   OVH, managed control plane SSD:        "csi-cinder-high-speed"   Bare metal, local NVMe:                "local-path" (Rancher) or                                          a custom provisioner  If you only have HDD-backed storage you will not meet Scylla's I/O requirements — use scripts/deploy-validator.sh --xfs-path on a bare-metal host instead. |
| scylla.scyllaVersion | string | `"6.2.3"` | Container image versions. Defaults match the testnet-conway production validators. |
| scylla.sysctls | list | `["fs.aio-max-nr=4082080"]` | Sysctls applied at the node level by the ScyllaCluster spec. |
| scylla.tuning | object | `{"enabled":false,"name":"scylla-tuning","nodeSelector":{"workload":"scylla"},"tolerations":[{"effect":"NoSchedule","key":"scylla-db","operator":"Equal","value":"true"}]}` | Optional perftune / IRQ-steering NodeConfig (scylla-operator performance tuning). When enabled, the chart emits a scylla.scylladb.com/v1alpha1 NodeConfig that tells the operator to run perftune on the selected nodes: pin Scylla to its exclusive cores (/etc/scylla.d/cpuset.conf), steer NIC IRQs OFF those cores, and apply kernel/net/disk-scheduler sysctls.  GKE-equivalent performance needs ALL THREE of these together, not just this flag:   1. a DEDICATED Scylla nodepool (taint + matching rack nodeAffinity/      tolerations so nothing else lands on those cores);   2. kubelet `cpuManagerPolicy=static` on that nodepool (so the static CPU      manager can grant exclusive cores — also requires the Guaranteed-QoS      pod that `rack.agentResources` above produces);   3. this NodeConfig (the perftune/IRQ steering itself).  Disabled by default: it only helps on a dedicated, statically-pinned nodepool and is a no-op (or worse) on a shared one. |
| scylla.tuning.name | string | `"scylla-tuning"` | NodeConfig metadata.name. |
| scylla.tuning.nodeSelector | object | `{"workload":"scylla"}` | Node selector that picks the dedicated Scylla nodes to tune. Must match the labels on your Scylla nodepool. |
| scylla.tuning.tolerations | list | `[{"effect":"NoSchedule","key":"scylla-db","operator":"Equal","value":"true"}]` | Tolerations so the operator's perftune DaemonSet pods can schedule onto the (tainted) dedicated Scylla nodes. |

## License

Apache 2.0.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
