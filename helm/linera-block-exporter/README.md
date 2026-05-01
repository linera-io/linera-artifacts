# linera-block-exporter

![Version: 0.1.2](https://img.shields.io/badge/Version-0.1.2-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.13.0](https://img.shields.io/badge/AppVersion-0.13.0-informational?style=flat-square)

Linera block exporter: a side-car that reads blocks from a validator's
storage backend (ScyllaDB) and pushes them to an indexer over gRPC.
Recommended on every validator — it lets the wider network reconstruct
chain history and powers the public explorer.

The block exporter MUST run in the same cluster as a Linera validator
and connect to the same ScyllaDB cluster. It cannot be operated
standalone: it depends on a running validator's database.

**Homepage:** <https://linera.io>

> Running a block exporter on your validator is **strongly
> encouraged**: it makes chain history available to the rest of the
> network without affecting the validator's hot path.

## Hard requirements

- Must be deployed in the **same Kubernetes cluster** as a Linera
  validator (this chart's [linera-validator](../linera-validator/)).
- Must connect to the **same ScyllaDB cluster** the validator uses.
- A reachable indexer endpoint to push blocks to.

If you don't already run a validator, install
[`linera-validator`](../linera-validator/) first. You also need an
indexer endpoint reachable from the cluster to receive the pushed
blocks.

## TL;DR

```bash
helm install validator-1-exporter \
  oci://ghcr.io/linera-io/charts/linera-block-exporter \
  --namespace linera \
  --set image.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera \
  --set image.tag=testnet_conway_release \
  --set storage.uri='scylladb:tcp:scylla-client.scylla.svc.cluster.local:9042' \
  --set destinations[0].kind=Indexer \
  --set destinations[0].endpoint=indexer.example.com \
  --set destinations[0].port=8081 \
  --set destinations[0].tls=ClearText
```

## How it works

The exporter is a StatefulSet. Each replica:

1. Waits for the validator's ScyllaDB to be initialized
   (`linera storage check-existence`).
2. Loads its TOML config (one per replica, keyed by the pod ordinal —
   see `templates/configmap.yaml`).
3. Waits for every configured indexer endpoint to respond on TCP.
4. Runs `linera-exporter run --storage <uri> --config-path <toml>
   --metrics-port <port>`.

Multiple replicas shard the work between them via the `id` field in
each TOML.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Linera infrastructure team |  | <https://github.com/linera-io> |

## Source Code

* <https://github.com/linera-io/linera-artifacts>
* <https://github.com/linera-io/linera-protocol>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| committeeDestination | bool | `true` |  |
| commonLabels | object | `{}` |  |
| destinations[0] | object | `{"endpoint":"","kind":"Indexer","port":8081,"tls":"ClearText"}` | One or more indexer endpoints to push blocks to. |
| destinations[0].endpoint | string | `""` | DNS name or IP of the indexer. |
| destinations[0].port | int | `8081` | gRPC port of the indexer. |
| destinations[0].tls | string | `"ClearText"` | TLS mode: "ClearText" (in-cluster) or "Tls" (e.g. external indexer behind a Gateway with cert-manager TLS). |
| exporter.affinity | object | `{}` |  |
| exporter.extraEnv | list | `[]` |  |
| exporter.extraVolumeMounts | list | `[]` |  |
| exporter.extraVolumes | list | `[]` |  |
| exporter.indexerReadinessCheck | object | `{"enabled":true,"image":"curlimages/curl:8.10.1","retryIntervalSeconds":5}` | Wait for each indexer destination to respond before starting. |
| exporter.indexerReadinessCheck.image | string | `"curlimages/curl:8.10.1"` | Image used for the curl probe. Defaults to upstream curlimages/curl. |
| exporter.livenessProbe | object | `{}` |  |
| exporter.nodeSelector | object | `{}` | Pod scheduling. |
| exporter.persistence | object | `{"accessMode":"ReadWriteOnce","enabled":true,"size":"1Gi","storageClass":""}` | Persistent volume claim template for exporter state. Disable for ephemeral storage (data lost on pod restart). |
| exporter.podAnnotations | object | `{}` |  |
| exporter.podLabels | object | `{}` |  |
| exporter.podSecurityContext.fsGroup | int | `65534` |  |
| exporter.podSecurityContext.runAsNonRoot | bool | `true` |  |
| exporter.podSecurityContext.runAsUser | int | `65534` |  |
| exporter.priorityClassName | string | `""` |  |
| exporter.readinessProbe | object | `{}` |  |
| exporter.replicas | int | `1` | Number of exporter replicas. Each replica gets its own TOML config (id = pod ordinal) so they can shard the work. |
| exporter.resources | object | `{}` | Resource requests and limits. |
| exporter.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| exporter.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| exporter.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| exporter.startupProbe | object | `{}` |  |
| exporter.storageInitCheck | object | `{"enabled":true,"retryIntervalSeconds":5}` | Wait for the validator's database to exist before starting. |
| exporter.terminationGracePeriodSeconds | int | `30` |  |
| exporter.tolerations | list | `[]` |  |
| exporter.topologySpreadConstraints | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.pullSecrets | list | `[]` |  |
| image.repository | string | `""` | Image with the linera + linera-exporter binaries (REQUIRED). The same image used by linera-validator works. |
| image.tag | string | `""` | Image tag. Defaults to .Chart.appVersion when empty. |
| limits.auxiliaryCacheSizeMb | int | `1024` |  |
| limits.blobCacheItemsCapacity | int | `8192` |  |
| limits.blobCacheWeightMb | int | `1024` |  |
| limits.blockCacheItemsCapacity | int | `8192` |  |
| limits.blockCacheWeightMb | int | `1024` |  |
| limits.persistencePeriodMs | int | `5000` |  |
| limits.workQueueSize | int | `256` |  |
| log.backtrace | string | `"1"` |  |
| log.level | string | `"info"` |  |
| nameOverride | string | `""` |  |
| ports.grpc | int | `8882` | gRPC port the exporter exposes for service-config peers. |
| ports.metrics | int | `9091` | Prometheus metrics port. |
| service.annotations | object | `{}` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| serviceMonitor.enabled | bool | `false` |  |
| serviceMonitor.interval | string | `"30s"` |  |
| serviceMonitor.labels | object | `{}` |  |
| serviceMonitor.scrapeTimeout | string | `"10s"` |  |
| storage.uri | string | `""` | Connection string for the validator's storage backend. Same value passed to linera-validator (typically "scylladb:tcp:scylla-client.scylla .svc.cluster.local:9042"). The exporter reads blocks from this database. |

## License

Apache 2.0.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
