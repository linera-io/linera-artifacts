# linera-validator

![Version: 0.1.8](https://img.shields.io/badge/Version-0.1.8-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.13.0](https://img.shields.io/badge/AppVersion-0.13.0-informational?style=flat-square)

Linera validator core: the shards (StatefulSet) and proxies (StatefulSet)
that together form a single validator on the Linera network.

This chart deploys the validator workload only. Storage backend
(ScyllaDB) and observability stack (Prometheus, Grafana, Loki, etc.)
are deployed separately. See the linera-validator-stack chart for
an umbrella that bundles everything.

**Homepage:** <https://linera.io>

A validator is composed of two StatefulSets: **shards** (workhorses
that process operations on chains) and **proxy** (gRPC entrypoint that
clients connect to). For a one-shot install that bundles the
ScyllaCluster CR, see the
[`linera-validator-stack`](../linera-validator-stack/) umbrella chart.

## TL;DR

```bash
# Obtain server.json (PRIVATE signing key) and genesis.json (PUBLIC)
# from the Linera network operators, then create a Kubernetes Secret:
kubectl create namespace linera
kubectl --namespace linera create secret generic validator-1-config \
  --from-file=serverConfig=./server.json \
  --from-file=genesisConfig=./genesis.json

# Install the chart.
helm install validator-1 \
  oci://ghcr.io/linera-io/charts/linera-validator \
  --namespace linera \
  --set image.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-validator \
  --set image.tag=testnet_conway_release \
  --set clientImage.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-client \
  --set clientImage.tag=testnet_conway_release \
  --set validator.existingSecret=validator-1-config
```

## Prerequisites

- Kubernetes 1.27+
- Helm 3.8+ (for OCI registry support)
- A storage backend reachable from the cluster. Default is ScyllaDB on
  `scylla-client.scylla.svc.cluster.local:9042`. Override `storage.uri`
  to point elsewhere.

## Validating templates locally

```bash
helm lint .
helm template demo . \
  --set image.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-validator \
  --set image.tag=testnet_conway_release \
  --set clientImage.repository=us-docker.pkg.dev/linera-io-dev/linera-public-registry/linera-client \
  --set clientImage.tag=testnet_conway_release \
  --set validator.serverConfigData='{}' \
  --set validator.genesisConfigData='{}'
```

## Examples

See [`docs/examples/`](../../docs/examples/) for ready-to-use values
files for common scenarios (single-node dev, GKE production, OVH, …).

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
| clientImage.digest | string | `""` | Image digest. Takes precedence over tag when set. |
| clientImage.repository | string | `""` | Image repository for the `linera` CLI. Empty falls back to `image`. |
| clientImage.tag | string | `""` | Image tag. Defaults to image.tag, then .Chart.appVersion. |
| commonLabels | object | `{}` | Extra labels applied to every resource produced by the chart. |
| dashboards.enabled | bool | `false` | Emit ConfigMaps labelled for the Grafana sidecar to pick up (https://github.com/grafana/helm-charts/tree/main/charts/grafana). OPT-IN: requires your Grafana install to have dashboard sidecar enabled. Most operators ship dashboards via their own GitOps, this stays out of the way by default. |
| dashboards.label | string | `"grafana_dashboard"` | Label the Grafana sidecar searches for. Most installs use `grafana_dashboard=1`; adjust if yours differs. |
| dashboards.labelValue | string | `"1"` |  |
| fullnameOverride | string | `""` | Optional override of the chart's full name (used as resource name prefix). |
| gateway.annotations | object | `{}` | Extra annotations on the Gateway resource (e.g. for external-dns / cert-manager integration). |
| gateway.className | string | `""` | gatewayClassName (e.g. "envoy"). |
| gateway.enabled | bool | `false` | **Recommended.** Create a Gateway API Gateway + GRPCRoute. Gateway API is the Kubernetes-recommended successor to Ingress (<https://kubernetes.io/docs/concepts/services-networking/ingress/>). Requires a Gateway API implementation in the cluster — Envoy Gateway (<https://gateway.envoyproxy.io/>) is a common pick and what we test against. |
| gateway.envoyBackendTrafficPolicy | object | `{"circuitBreaker":{"maxConnections":100000,"maxParallelRequests":100000,"maxParallelRetries":10000,"maxPendingRequests":100000,"maxRequestsPerConnection":0},"enabled":false,"http2":{"initialConnectionWindowSize":67108864,"initialStreamWindowSize":16777216,"maxConcurrentStreams":1000000},"timeout":{"http":{"requestTimeout":"168h"}}}` | Envoy Gateway BackendTrafficPolicy targeting the validator GRPCRoute. Bumps the upstream cluster's circuit-breaker limits and HTTP/2 stream cap so bursty browser-driven gRPC-Web traffic doesn't hit Envoy's defaults (max_connections=1024, max_pending_requests= 1024, max_requests=1024) and surface to clients as 503 with `response_flags=UO` (upstream overflow). Browsers mislabel these 503s as CORS errors because no Allow-Origin header rides on a 5xx response — without this policy a public validator looks broken from a browser when traffic spikes even though the proxy itself is healthy.  Envoy Gateway only — opt-in for portability. Other Gateway API implementations need their own equivalent (e.g. Istio `DestinationRule.connectionPool`). |
| gateway.envoyClientTrafficPolicy | object | `{"enabled":false,"timeout":{"http":{"idleTimeout":"168h"}}}` | Opt-in ClientTrafficPolicy on the validator Gateway (downstream client↔Envoy side); the only place to set Envoy's HTTP stream-idle timeout (~5min default). enabled:false renders nothing; enabling affects the whole Gateway. timeout passed through 1:1 to spec.timeout (Envoy Gateway validates it); same Go-style durations. |
| gateway.hostname | string | `""` | Hostname for the validator. external-dns can manage the corresponding DNS record from this annotation. |
| gateway.tlsSecretName | string | `""` | TLS Secret produced by cert-manager (or any other source). |
| image.digest | string | `""` | Image digest (e.g. "sha256:..."). Takes precedence over tag when set — use for immutable, content-addressed pins. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.pullSecrets | list | `[]` | Pull secrets for private registries. |
| image.repository | string | `""` | Image repository for linera-server / linera-proxy (REQUIRED). Since the upstream image split this is `linera-validator`, NOT `linera`. |
| image.tag | string | `""` | Image tag. Defaults to .Chart.appVersion if empty. |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` | **DEPRECATED / maintenance mode.** Create a Kubernetes Ingress. The Kubernetes project has placed the Ingress API in feature freeze and recommends Gateway API for new deployments — see <https://kubernetes.io/docs/concepts/services-networking/ingress/>. Prefer the `gateway` block below for new installs. This option is kept for operators whose clusters only ship an Ingress controller. |
| ingress.hosts | list | `[]` |  |
| ingress.tls | list | `[]` |  |
| log.backtrace | string | `"0"` | RUST_BACKTRACE value. "0" (default): no Rust stack traces in logs. Anyhow error chains                (`0: ..., 1: ...`) are still emitted — those are                the useful part; only the tokio runtime frames                disappear. "1":           short backtrace (file + line per frame). "full":        full symbolic backtrace. Only set this when                actively debugging — it makes routine errors                look like panics. |
| log.level | string | `"info"` | RUST_LOG value applied to every linera process. |
| nameOverride | string | `""` | Optional override of the chart name. |
| networkName | string | `""` | Network identifier (used for service discovery in some optional subcomponents). Free-form, e.g. "testnet-conway" or "my-network". |
| networkPolicy.defaultDeny | bool | `false` | Add a deny-all NetworkPolicy that covers every pod in the release namespace. Only flip on if you've audited the other workloads in this namespace — this will break any pod that lacks an explicit allow rule. |
| networkPolicy.enabled | bool | `false` | Emit NetworkPolicy resources (proxy + shards + optional default-deny). Harmless on clusters without an enforcer. |
| networkPolicy.extraEgress | list | `[]` | Extra egress rules, appended to both proxy and shard policies. Must include at least your storage backend (ScyllaDB, RocksDB sidecar endpoint, etc.) and any observability push targets. |
| networkPolicy.metricsScrapeFrom | list | `[]` | Sources allowed to scrape /metrics on proxies + shards. Common override: your Prometheus / Alloy namespace. |
| networkPolicy.proxyIngressFrom | list | `[]` | Sources allowed to reach the proxy on the client port. Leave empty to allow from anywhere (public gRPC endpoint). Typical override: restrict to an ingress/gateway namespace. |
| otlpExporterEndpoint | string | `""` | OpenTelemetry OTLP endpoint. Empty = tracing disabled. |
| ports.metrics | int | `21100` | Prometheus metrics port (every component listens here). |
| ports.proxy | int | `19100` | gRPC port the proxy listens on for client connections. |
| ports.proxyInternal | int | `20100` | gRPC port for inter-proxy communication. |
| ports.shard | int | `19100` | gRPC port for shard inter-process communication. |
| prometheusRule.alerts | object | `{"blockProduction":false,"chainCorrectness":false,"scylla":false,"scyllaBackup":false,"storage":false,"validatorLatency":false}` | Optional extra alert groups, layered on top of the always-on core alerts (validator down, shard restart, proxy gRPC latency). Each toggle gates one group and is OFF by default: enable only the ones whose metrics your Prometheus actually scrapes, so you don't ship rules that can never fire (or fire on absent data). All of these require `prometheusRule.enabled: true`. |
| prometheusRule.alerts.blockProduction | bool | `false` | Block production stalled (linera_num_blocks flat for 15m while the shard is up). |
| prometheusRule.alerts.chainCorrectness | bool | `false` | Chain correctness (InboxGapDetected / CorruptedChainState). Critical, validator-internal, cannot self-heal. Recommended. |
| prometheusRule.alerts.scylla | bool | `false` | ScyllaDB storage backend (read/write p99 latency, I/O delay, target down, process restart). Requires your Prometheus to scrape native `scylla_*` metrics from your Scylla cluster. |
| prometheusRule.alerts.scyllaBackup | bool | `false` | Scylla Manager backups (overdue / failed). Only meaningful if you run Scylla Manager against your cluster. |
| prometheusRule.alerts.storage | bool | `false` | PVC capacity (critical / warning / filling-up). Requires kube-state-metrics + kubelet volume stats in your Prometheus. |
| prometheusRule.alerts.validatorLatency | bool | `false` | Validator request latency (linera_proxy/server_request_latency p99 > 1s). Always available — these come from the validator's own metrics endpoint that this chart already exposes. |
| prometheusRule.enabled | bool | `false` | Create a PrometheusRule with the default Linera alerts (validator down, shard restart, proxy gRPC latency). Enable additional groups via `alerts.*` and extend with `extraRules` below. OPT-IN: requires prometheus-operator + the PrometheusRule CRD installed in the cluster. |
| prometheusRule.extraRules | list | `[]` | Additional alert / recording rules merged into the default set. |
| prometheusRule.labels | object | `{}` | Extra labels on the PrometheusRule (match your Prometheus's ruleSelector if it filters by label). |
| prometheusRule.recordingRules | object | `{"enabled":false}` | Pre-computed recording rules. Two PrometheusRules are emitted: the linera `linera:*:rate1m` aggregates (execution, request, storage, view metrics) AND the ScyllaDB rules (coordinator latency percentiles, CQL rates, per-table latencies, Scylla Manager progress) used by the standard Scylla dashboards. Useful when a local monitoring stack answers Grafana queries and you want faster long-window panels. The Scylla rules reference native `scylla_*` metrics; rules whose inputs are absent simply produce nothing. Leave OFF when metrics are forwarded to a central backend that already does its own recording. |
| proxies.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchLabels."app.kubernetes.io/component" | string | `"proxy"` |  |
| proxies.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey | string | `"kubernetes.io/hostname"` |  |
| proxies.cli | object | `{"blobCacheSize":1000,"certificateCacheSize":5000,"certificateRawCacheSize":50000,"confirmedBlockCacheSize":10000,"eventCacheSize":20000,"extraArgs":[],"storageMaxCacheEntries":500000,"storageMaxCacheFindKeyValuesSize":10000000,"storageMaxCacheFindKeysSize":200000000,"storageMaxCacheSize":1000000000,"storageMaxCacheValueSize":500000000,"storageMaxFindKeyValuesEntrySize":1000000,"storageMaxFindKeysEntrySize":1000000,"storageMaxValueEntrySize":1000000}` | linera-proxy CLI flags. Same conventions as shards.cli (every flag is `--<kebab-case-key> <value>`, null values are skipped). Defaults are the values currently in use on the testnet-conway validators. |
| proxies.extraEnv | list | `[]` | Extra environment variables. |
| proxies.extraVolumeMounts | list | `[]` |  |
| proxies.extraVolumes | list | `[]` | Extra volumes / volume mounts. |
| proxies.livenessProbe | object | `{}` | Probe overrides. |
| proxies.nodeSelector | object | `{}` | Pod scheduling. Default podAntiAffinity (hard, by hostname) keeps each proxy on a distinct node so PDB minAvailable holds during a node drain. Operators on a single-node cluster must override `affinity` here OR keep replicas: 1. |
| proxies.podAnnotations | object | `{}` | Pod annotations and labels. |
| proxies.podDisruptionBudget | object | `{"enabled":true,"maxUnavailable":null,"minAvailable":1}` | PodDisruptionBudget for the proxy pods. Protects against simultaneous evictions during node drains / voluntary disruptions. Set only one of `minAvailable` / `maxUnavailable`. Not created for shards by design: each shard holds a unique slice of validator state, so any voluntary disruption is a correctness risk — operators must drain shards manually. |
| proxies.podDisruptionBudget.maxUnavailable | string | `nil` | Maximum proxy pods that may be unavailable at once. Leave unset when `minAvailable` is used. |
| proxies.podDisruptionBudget.minAvailable | int | `1` | Minimum proxy pods that must stay available (integer or percentage string like "50%"). Mutually exclusive with `maxUnavailable`. |
| proxies.podLabels | object | `{}` |  |
| proxies.podSecurityContext | object | `{}` | Pod-level security context. |
| proxies.priorityClassName | string | `""` | Pod priority class name. |
| proxies.readinessProbe | object | `{}` |  |
| proxies.replicas | int | `2` | Number of proxy replicas. Default 2 + PDB minAvailable=1 below tolerates one node drain without losing client-facing traffic. Single-node clusters must set replicas: 1 and disable podDisruptionBudget. |
| proxies.resources | object | `{"limits":{"cpu":"2","memory":"6Gi"},"requests":{"cpu":"1","memory":"4Gi"}}` | Resource requests and limits. Defaults sized from observed steady state on the testnet-conway production validators (GKE, no resource cap historically): linera-proxy plateaus around 3.5 GiB p50 / 4.0 GiB p95 / 5.0 GiB max per replica, with ~0.45 cpu p95 and ~0.66 cpu max. Set as Burstable QoS. Operators with very different traffic should override here. |
| proxies.securityContext | object | `{}` | Container-level security context. |
| proxies.service | object | `{"annotations":{},"loadBalancerIP":"","type":"ClusterIP"}` | External Service for client traffic. |
| proxies.service.annotations | object | `{}` | Annotations on the proxy Service (e.g. cloud LB hints). |
| proxies.service.loadBalancerIP | string | `""` | Optional static IP (for cloud providers that respect this). |
| proxies.service.type | string | `"ClusterIP"` | Service type. ClusterIP for in-cluster only, LoadBalancer for cloud LBs, NodePort for bare-metal exposure. |
| proxies.startupProbe | object | `{}` |  |
| proxies.terminationGracePeriodSeconds | int | `10` | Termination grace period in seconds. |
| proxies.tolerations | list | `[]` |  |
| proxies.topologySpreadConstraints | list | `[]` |  |
| serviceAccount.annotations | object | `{}` | Annotations applied to the ServiceAccount (useful for workload-identity setups). |
| serviceAccount.create | bool | `true` | Create a ServiceAccount. |
| serviceAccount.name | string | `""` | ServiceAccount name. Empty = derived from chart name. |
| serviceMonitor.enabled | bool | `false` | Create a ServiceMonitor so a Prometheus Operator can scrape both shards and proxies. OPT-IN: most operators wire scraping with their own observability stack, this chart stays out of the way. Enable only if you run prometheus-operator in the same cluster. |
| serviceMonitor.interval | string | `"30s"` | Scrape interval. |
| serviceMonitor.labels | object | `{}` | Extra labels on the ServiceMonitor (e.g. release: prometheus if your Prometheus selects by that label). |
| serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout. |
| shards.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchLabels."app.kubernetes.io/component" | string | `"shards"` |  |
| shards.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey | string | `"kubernetes.io/hostname"` |  |
| shards.cli | object | `{"blobCacheSize":1000,"blockCacheSize":20000,"certificateCacheSize":5000,"certificateRawCacheSize":50000,"chainWorkerTtlMs":300000,"confirmedBlockCacheSize":10000,"eventCacheSize":20000,"executionStateCacheSize":20000,"extraArgs":[],"storageMaxCacheEntries":500000,"storageMaxCacheFindKeyValuesSize":10000000,"storageMaxCacheFindKeysSize":200000000,"storageMaxCacheSize":1000000000,"storageMaxCacheValueSize":500000000,"storageMaxFindKeyValuesEntrySize":1000000,"storageMaxFindKeysEntrySize":1000000,"storageMaxValueEntrySize":1000000}` | linera-server CLI flags. Every flag is passed as `--<kebab-case-key> <value>` and is omitted entirely when the value is null. Defaults are the values currently in use on the Linera testnet-conway validators. Override per cluster as needed. |
| shards.cli.extraArgs | list | `[]` | Free-form extra arguments appended verbatim to the linera-server command line. Each entry is added on its own line. |
| shards.extraEnv | list | `[]` | Extra environment variables added to the shard container. |
| shards.extraVolumeMounts | list | `[]` |  |
| shards.extraVolumes | list | `[]` | Extra volumes / volume mounts (for advanced use cases). |
| shards.livenessProbe | object | `{}` | Probe overrides. Empty = sensible defaults baked into the template. |
| shards.nodeSelector | object | `{}` | Pod scheduling. Default podAntiAffinity (hard, by hostname) keeps each shard on a distinct node so a single node loss takes out at most one shard. Operators on smaller clusters (fewer nodes than shard replicas) must override `affinity` here OR add more nodes, otherwise excess shards stay Pending. |
| shards.podAnnotations | object | `{}` | Pod annotations. |
| shards.podLabels | object | `{}` | Pod labels (in addition to the default app.kubernetes.io/* labels). |
| shards.podSecurityContext | object | `{}` | Pod-level security context. |
| shards.priorityClassName | string | `""` | Pod priority class name. |
| shards.readinessProbe | object | `{}` |  |
| shards.replicas | int | `4` | Number of shard replicas. |
| shards.resources | object | `{"limits":{"cpu":"2","memory":"12Gi"},"requests":{"cpu":"1","memory":"8Gi"}}` | Resource requests and limits. Defaults sized from observed steady state on the testnet-conway production validators (GKE, no resource cap historically): linera-server plateaus around 6.8 GiB p50 / 8.5 GiB p95 / 9.5 GiB max per shard, with bursty <0.5 cpu p95 and ~0.6 cpu max. Set as Burstable QoS — req covers steady state, lim covers plateau + ~25 % headroom. Operators with very different chain workloads should override here. |
| shards.securityContext | object | `{}` | Container-level security context. |
| shards.serverTokioThreads | string | `""` | Tokio worker threads per shard. Empty = one per CPU (Tokio default). |
| shards.startupProbe | object | `{}` |  |
| shards.terminationGracePeriodSeconds | int | `10` | Termination grace period in seconds. |
| shards.tolerations | list | `[]` |  |
| shards.topologySpreadConstraints | list | `[]` |  |
| storage.dual | bool | `false` | Enable dual storage mode (RocksDB local + ScyllaDB remote). Recommended for development only. |
| storage.replicationFactor | int | `1` | Storage replication factor (must match the ScyllaDB cluster RF). |
| storage.rocksdbSize | string | `"2Gi"` | RocksDB volume size per shard (only used when storage.dual is true). |
| storage.rocksdbStorageClass | string | `""` | StorageClass for the RocksDB PVCs. Empty = cluster default. |
| storage.uri | string | `"scylladb:tcp:scylla-client.scylla.svc.cluster.local:9042"` |  |
| useComponentPrefix | bool | `false` | Prefix component resource names (StatefulSets/Services) with `<fullname>-`. Default false = clean names (proxy, shards, proxy-internal) matching what linera-network-init mints. Set true for legacy deployments whose minted server config references the prefixed names (validator-proxy, ...) — flipping it on a live release RENAMES StatefulSets/Services (delete + recreate) and breaks the internal gRPC mesh unless the minted hostnames are changed to match. |
| validator.existingSecret | string | `""` | Use an existing Secret instead of inlining configs above. The Secret must contain two keys: "serverConfig" and "genesisConfig". |
| validator.genesisConfigData | string | `""` | Genesis config JSON (public). Distributed to every validator in the same network. Inline as a string here, or use existingSecret. |
| validator.serverConfigData | string | `""` | Server config JSON (PRIVATE — contains the validator signing key). Inline as a string here, or use existingSecret. |
| validatorLabel | string | `""` | Validator label exposed to external monitoring systems. Free-form, e.g. "validator-1" or "us-east-pilot". |

## License

Apache 2.0.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
