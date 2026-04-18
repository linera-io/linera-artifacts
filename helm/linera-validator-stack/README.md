# linera-validator-stack

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.13.0](https://img.shields.io/badge/AppVersion-0.13.0-informational?style=flat-square)

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
| file://../linera-block-exporter | linera-block-exporter | 0.1.0 |
| file://../linera-validator | linera-validator | 0.1.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| linera-block-exporter | object | `{"destinations":[],"enabled":false,"storage":{"uri":"scylladb:tcp:scylla-client.scylla.svc.cluster.local:9042"}}` | --------------------------------------------------------------------------- |
| linera-validator.enabled | bool | `true` |  |
| scylla | object | `{"agentImage":"scylladb/scylla-manager-agent","agentVersion":"3.4.0@sha256:441403aed8880cad1feef68aa7a8ee9ffd99a458dc1dcff3dc54ce5bf3cb07b7","backups":{"cron":"0 4 * * *","enabled":false,"keyspaces":["kv"],"location":"","name":"daily-backup","numRetries":3,"rateLimit":["50"],"retentionDays":90},"config":{"create":true,"data":{"commitlog_segment_size_in_mb":64,"query_tombstone_page_limit":200000}},"datacenter":"validator","developerMode":false,"enabled":true,"name":"scylla","namespace":"scylla","rack":{"members":1,"name":"rack","placement":{"nodeAffinity":{},"tolerations":[]},"resources":{"limits":{"cpu":"7","memory":"51Gi"},"requests":{"cpu":"7","memory":"51Gi"}},"storage":{"capacity":"1000Gi","storageClassName":""}},"scyllaImage":"scylladb/scylla","scyllaVersion":"6.2.3","sysctls":["fs.aio-max-nr=4082080"]}` | --------------------------------------------------------------------------- Requires scylla-operator to be installed in the cluster (CRDs). Set scylla.enabled=false to bring your own storage backend. |
| scylla.backups | object | `{"cron":"0 4 * * *","enabled":false,"keyspaces":["kv"],"location":"","name":"daily-backup","numRetries":3,"rateLimit":["50"],"retentionDays":90}` | Backup schedule (Scylla Manager). Set to {} to disable. |
| scylla.config | object | `{"create":true,"data":{"commitlog_segment_size_in_mb":64,"query_tombstone_page_limit":200000}}` | ConfigMap consumed by the ScyllaCluster as its scylla.yaml. Created in the same namespace as the cluster. |
| scylla.datacenter | string | `"validator"` | Datacenter name (informational, exposed as a Scylla DC label). |
| scylla.developerMode | bool | `false` | Enable ScyllaCluster developerMode. Skips strict cpuset/CPU pinning, fewer resource checks. NEVER set true in production — only useful for kind / minikube / single-node test clusters. |
| scylla.name | string | `"scylla"` | ScyllaCluster name. Used by the auto-generated client Service (scylla-client.<namespace>.svc.cluster.local). |
| scylla.namespace | string | `"scylla"` | Namespace where the ScyllaCluster lives. The chart does NOT create this namespace — create it ahead of time or let scylla-operator do it. |
| scylla.rack | object | `{"members":1,"name":"rack","placement":{"nodeAffinity":{},"tolerations":[]},"resources":{"limits":{"cpu":"7","memory":"51Gi"},"requests":{"cpu":"7","memory":"51Gi"}},"storage":{"capacity":"1000Gi","storageClassName":""}}` | One ScyllaCluster rack. Add more entries to spread across racks. |
| scylla.rack.storage.storageClassName | string | `""` | StorageClass for the Scylla PVCs. Empty = cluster default (rarely what you want for ScyllaDB).  Recommended values by provider:   GKE, regional PD-SSD:                   "premium-rwo"   GKE, zonal local SSDs (NVMe, fastest): "local-ssd-resource-adapter"                                          (requires the Local SSD CSI                                          driver enabled on the cluster                                          and matching nodepool with                                          --local-ssd-count > 0)   EKS, gp3 SSD:                          "gp3"   AKS, Premium SSD v2:                   "managed-premium"   OVH, managed control plane SSD:        "csi-cinder-high-speed"   Bare metal, local NVMe:                "local-path" (Rancher) or                                          a custom provisioner  If you only have HDD-backed storage you will not meet Scylla's I/O requirements — use scripts/deploy-validator.sh --xfs-path on a bare-metal host instead. |
| scylla.scyllaVersion | string | `"6.2.3"` | Container image versions. Defaults match the testnet-conway production validators. |
| scylla.sysctls | list | `["fs.aio-max-nr=4082080"]` | Sysctls applied at the node level by the ScyllaCluster spec. |

## License

Apache 2.0.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
