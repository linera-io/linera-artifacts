# Troubleshooting

Symptoms you are likely to see in `docker compose logs` (or `kubectl logs`) and
what to do about them.

## `NewCommittee event missing in storage`

**Symptom** — on a shard, repeatedly, and your validator answers few or no
requests even though it is reachable and its ports are open:

```
WARN process_confirmed_block{chain_id=… height=…}: linera_storage:
  get_or_load_committee: NewCommittee event missing in storage
  epoch=Epoch(47)
  event_id=EventId { chain_id: <admin-chain-id>, stream_id: StreamId {
    application_id: System, stream_name: StreamName(00) }, index: 47 }
```

**What it means** — your validator does not have the committee for that epoch,
so it cannot check the signatures on blocks from any chain still at that epoch,
and it rejects them. This is not a warning you can ignore: the block is not
stored and the chain does not advance on your node.

It happens when a validator **joins an existing network after genesis**. Each
committee change is recorded as an event on the network's *admin chain*, and a
validator only has the events from blocks it processed itself. A validator
admitted at epoch 48 never saw epochs 1–47, and nothing backfills them
automatically.

The `chain_id` inside `event_id` **is** the admin chain — you do not need to look
it up anywhere else. `index` is the epoch whose committee is missing.

**Fix** — replay the admin chain into your validator. This needs no keys: a
followed chain is one your wallet tracks without being able to sign for it.

```bash
# 1. Track and download the admin chain locally.
linera wallet follow-chain --sync <admin-chain-id>

# 2. Push it to your validator.
linera validator sync grpcs:validator.example.com:443 \
    --chains <admin-chain-id>
```

**Verify it worked** by confirming the warnings stop, not by trusting the
command's output. If the wallet you ran step 2 from does not actually hold the
chain, the sync returns success having sent nothing — it compares your local
height against the validator's and exits early when there is nothing to send.
Step 1 is what makes sure there is.

Add `--check-online` to step 2 if you want it to verify the validator is
reachable and version-compatible before it starts.

## `Blob not found ChainDescription:…`

**Symptom** — `WARN`/`ERROR` from the proxy on `download_blob` and
`blob_last_used_by_certificate`:

```
ERROR grpc_request:download_blob{method="download_blob"}: linera_proxy::grpc:
  error=status: 'Some requested entity was not found',
  self: "Blob not found ChainDescription:<hash>"
```

**What it means** — a client asked your validator for data about a chain created
before your validator joined. You do not have it, so the request fails and the
client asks a different validator.

**What to do** — normally nothing. These are expected on a freshly joined
validator and become less frequent as it accumulates state: when a client
submits a block whose certificate needs a blob you are missing, it uploads that
blob and retries automatically.

They are worth a second look only if they persist at a high rate long after
joining, or if they appear alongside the epoch warning above — in which case fix
that first, since a validator that cannot accept certificates never accumulates
anything.

## Checking whether your validator is actually serving

Reachability is not the same as usefulness — a validator can pass a TCP health
check while rejecting every block. The quickest signals, all from the metrics
your stack already exposes (see [Observability](OBSERVABILITY.md)):

```promql
# Blocks executed. Flat at zero while the network is active means you are
# accepting nothing.
sum by (shard) (rate(linera_num_blocks_executed[5m]))

# Errors by type, from the proxy and the shards.
sum by (error_type) (rate(linera_proxy_request_error[5m]))
sum by (error_type) (rate(linera_server_request_error[5m]))
```

The `Performance` dashboard shipped in `docker/dashboards/` puts these on one
page along with request, execution and storage latency.
