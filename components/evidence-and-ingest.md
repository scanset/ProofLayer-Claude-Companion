# Evidence & Ingest

**Status: built.**

## The envelope (`AssessorPackage` / `ResultEnvelope`)

Every scan produces exactly one signed JSON envelope — the wire-format unit of
evidence. Top-level fields:

| Field | Meaning |
|---|---|
| `result_id` | UUID for this result |
| `schema_version` | Envelope schema (e.g. `2.1.1`) |
| `agent` | The executor (scanner identity) info |
| `host` | The subject the attestation is about (see note below) |
| `started_at` / `completed_at` | ISO-8601 UTC bounds |
| `replay_hash` + `replay_hash_version` | The deterministic posture hash — see [replay-hash.md](replay-hash.md) |
| `signature` | ECDSA-P256 block: signer id, public key, cert chain, transparency inclusion proof |
| `identity_status` | PKI bootstrap status of the signer |
| `observations` | The collected evidence items, each with a content hash |

> **Executor vs subject.** Until the full `Subject` envelope shape lands,
> `envelope.host` carries *executor* identity whose meaning depends on scan
> shape: for multi-target (fan-out) and discovery scans it's the **scanner
> identity** (`host_type=esp.scanner`); for single-host CTNs it's the **target
> host**. The asset(s) an envelope covers are recorded alongside the result, so
> evidence is attributed to the right asset regardless of executor.

## One ingest path

Every scan runs **in-process** — the server dispatches the `esp_assessor` CLI
over a channel, ingests the signed envelope it returns, and persists it through
a single ingest path. Ingest:

```
verify signature + cert chain
  → append signer identity to the transparency log (inclusion proof)
  → persist scan_results + ctn_results (per-CTN×OBJECT replay leaves)
  → upsert hosts / assets, update last_seen + last_scan
  → record the posture event (first_seen | drift | reversion | stable)
```

## What gets persisted

Conceptually, each ingested scan is stored as:

- the **envelope + signature** (the full result, attributed to its asset),
- the **per-CTN-per-OBJECT replay-hash leaves** (the fine-grained hashes that
  roll up into the policy and envelope hashes),
- the scanned **host/asset identity**, and
- an **append-only posture ledger** of state changes over time — see
  [posture-and-drift.md](posture-and-drift.md).

## How an evaluator reads it

Operator (`/api/inventory/evidence/*`): `subjects`, `posture-history`,
`state-chain`, `ctn-drift`, `findings`, `ctn-results`, `verify-hash`,
`reproducibility`. AO oversight (`/cmr-api/evidence/by-asset`, `…/assets/*`, and
the on-demand `/cmr-api/verify/{replay_hash}`). Both read the same persisted
evidence; the surface differs, the data doesn't.
