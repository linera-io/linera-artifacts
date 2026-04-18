# Examples

Ready-to-use values files for common deployment scenarios.

| File                              | Scenario                                                    |
|-----------------------------------|-------------------------------------------------------------|
| [`single-node.yaml`](single-node.yaml) | Smallest possible install on a dev cluster (kind/minikube). |
| [`gke-production.yaml`](gke-production.yaml) | GKE with workload identity, PD-SSD, Gateway API.            |
| [`gke-hands-off.yaml`](gke-hands-off.yaml) | GKE umbrella install with NVMe local SSDs (one-shot).       |
| [`ovh-bare-metal.yaml`](ovh-bare-metal.yaml) | OVH managed Kubernetes with bare-metal node pool.           |
| [`ha-multi-validator.yaml`](ha-multi-validator.yaml) | Production HA: 3 proxies, topology spread, anti-affinity.   |
| [`dedicated-storage-nodes.yaml`](dedicated-storage-nodes.yaml) | Pin ScyllaDB (and optionally RocksDB) to a tainted nodepool with fast local SSDs. Umbrella chart. |
| [`cert-manager-clusterissuer.yaml`](cert-manager-clusterissuer.yaml) | ACME ClusterIssuers (staging + prod) for use with the Gateway API path. |

All examples target the standalone `linera-validator` chart unless
noted otherwise. To use one:

```bash
helm install <release> oci://ghcr.io/linera-io/charts/linera-validator \
  --version <chart-version> \
  --namespace linera --create-namespace \
  -f docs/examples/<file>.yaml
```

You will also need:

- A Secret with `serverConfig` + `genesisConfig` — obtain these from
  the Linera network operators.
- An accessible ScyllaDB cluster (or use `linera-validator-stack` to
  provision one via `scylla-operator`).
