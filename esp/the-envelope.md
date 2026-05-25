# The Envelope (AssessorPackage)

What a scan emits: one signed `AssessorPackage`. This page is the **wire shape** —
the fields, the observation model, the filtering tiers, and the replay-hash
invariants. How Prooflayer *ingests, signs, and stores* it is in
[../components/evidence-and-ingest.md](../components/evidence-and-ingest.md);
the hash itself is in [../components/replay-hash.md](../components/replay-hash.md).

> Reflects the normative ESP canonical schema (v2) — full spec: [spec/09](spec/09_ESP_Canonical_Schema_v2_1_1.md).
> One envelope per scan, regardless of how many `.esp` files were scanned —
> "single envelope" design.

---

## 1. Top-level structure

```json
{
  "envelope":     { "result_id", "schema_version", "agent", "host",
                    "started_at", "completed_at",
                    "replay_hash", "replay_hash_version",
                    "signature", "identity_status" },
  "summary":      { "total_policies", "passed", "failed", ... },
  "observations": [ ... ],     // first-class evidence (peer to policies)
  "policies":     [ ... ]      // per-policy results, cite observations by uuid
}
```

Three parts do the work: the **envelope** (identity + timing + hash +
signature), the **observations** (the evidence), and the **policies** (the
verdicts that cite evidence).

---

## 2. The envelope header

| Field | Meaning |
|---|---|
| `result_id` | UUID for this scan result |
| `schema_version` | e.g. `2.1.0` |
| `agent` | the executor (id, name, version, type) |
| `host` | **what was scanned** — polymorphic (see §3) |
| `started_at` / `completed_at` | ISO-8601 UTC |
| `replay_hash` + `replay_hash_version` | the deterministic posture hash + which scheme (`1` default, `2` per-OBJECT) |
| `signature` | algorithm, key id, value, cert chain, transparency proof |
| `identity_status` | the **signer's** PKI bootstrap state (not the subject's) |

---

## 3. `host` is polymorphic

`host` describes the scanned subject and is deliberately not VM-shaped — a VM, a
cloud account, an identity tenant, and a SaaS tenant are all "hosts." The
discriminator is a free-string **`host_type`** in dotted `<provider>.<kind>`
form, plus a `host_id` and a type-specific `attrs` map.

```json
{ "host_type": "azure.vm", "host_id": "vm-prooflayer-demo",
  "hostname": "vm-prooflayer-demo", "os": "linux", "arch": "x86_64",
  "attrs": { "subscription_id": "...", "resource_group": "...", "location": "eastus" } }
```

Only `host_type` + `host_id` are required; `hostname`/`os`/`arch` appear for
VM-like hosts and are omitted for abstract ones (accounts, tenants). Recommended
(non-normative) `host_type`s: `linux.vm`, `windows.vm`, `azure.vm`,
`azure.subscription`, `aws.ec2`, `aws.account`, `gcp.vm`, `gcp.project`,
`m365.tenant`, `entra.tenant`, `k8s.cluster`. **Consumers MUST NOT reject an
unknown `host_type`** — new ones are added by convention, not schema revision.

`(host_type, host_id)` is the uniqueness key; `host_id` should be stable across
scans (machine-id, account number, tenant GUID) and **never** derived from
scan-time state like IP/hostname.

> Prooflayer's executor-vs-subject nuance (when `host` is the scanner identity
> vs the target) is in [../components/evidence-and-ingest.md](../components/evidence-and-ingest.md).

---

## 4. Observations — evidence as a first-class entity

An **observation** is one act of collection: a file read, a command, an API
call. Evidence lives once in the top-level `observations[]` array — *not* inside
each policy — and policies cite it by uuid. A single `/etc/os-release` read used
by ten policies appears **once** in `observations[]` and ten times across their
`observation_refs[]`.

```json
{ "uuid": "0b2e5c0a-…", "host_ref": { "host_type": "azure.vm", "host_id": "…" },
  "collected_at": "2026-04-20T11:30:14Z",
  "method": { "kind": "file_read", "params": { "path": "/etc/os-release" } },
  "content_hash": "sha256:3a7bd3e…",
  "body": { "bytes_base64": "…", "encoding": "utf-8" } }
```

| Field | Note |
|---|---|
| `uuid` | stable for the envelope's lifetime, **not** across scans |
| `host_ref` | `{host_type, host_id}` |
| `collected_at` | timestamp — **not** in the replay hash |
| `method` | `{kind, params}` — `file_read`/`exec`/`http`/`sdk_call`/`query`; `params` is what reproducibility cites |
| `content_hash` | SHA-256 over the canonical body bytes (`sha256:` prefix) |
| `body` | the payload; **dropped** in attestation/summary views (only `content_hash` kept) |

Observations do **not** feed the replay hash — adding, reordering, or
re-uuid'ing them never changes it.

---

## 5. Policy results

Each entry in `policies[]` is one policy's verdict: `policy_id`, `outcome`
(Pass/Fail/Error — see [evaluation-and-outcomes.md](evaluation-and-outcomes.md)),
`criticality`, counts, `control_mappings`, `observation_refs[]` (uuids into
`observations[]`), and `findings[]` (the validation failures). The v1.x inline
`policies[].evidence` field is **gone** — evidence is referenced, not embedded.

---

## 6. Sensitivity tiers — one shape, consumer filtering

The agent emits **one** signed shape. Narrower views are produced by *dropping
fields*, and because the replay hash is invariant under every recipe, a filtered
extract stays verifiably linked to the original by hash equality:

| Recipe | observation bodies | observation_refs | content_hash | findings | use |
|---|---|---|---|---|---|
| **Summary** | absent | absent | present | absent | CI/CD pass-fail |
| **Attestation** | absent | present | present | absent | dashboards, SIEM/SOAR, audit proof |
| **Full** (as emitted) | present (+ reproducibility) | present | present | present | remediation, investigation, auditor reproduction |

There is **no `--format` flag** — the agent always emits Full and signs that;
filtering happens consumer-side. (The signature covers the unfiltered envelope;
a consumer re-signing a filtered extract produces a *distinct* attestation.)

---

## 7. Replay-hash invariants (what's in, what's out)

The hash covers **`(intent, contract, outcome)`** per criterion, rolled up
through the CRI tree. It **excludes** `host`, all of `observations[]` (uuids,
bodies, content hashes), `started_at`/`completed_at`, `signature`,
`identity_status`, and `result_id`. Therefore:

- same posture on two different hosts → **same** `replay_hash` (cross-host dedup);
- same policy re-run on the same host later → **same** hash (drift = hash changed);
- re-serializing (key reorder, whitespace) → **same** hash.

Full treatment: [../components/replay-hash.md](../components/replay-hash.md); the
byte-exact verifier contract is
[../components/replay-hash-canonical-spec.md](../components/replay-hash-canonical-spec.md),
and how the envelope is signed, logged, and verified end-to-end is
[../components/transparency-and-verifiable-evidence.md](../components/transparency-and-verifiable-evidence.md).

---

## 8. Reproducibility & OSCAL

The **reproducibility** block turns observations into an assessor-facing
`commands[]` list (the command, cwd, exit code, stdout hash, and every policy
that cited it) — the manual-reproduction story. And the observation model maps
**1:1 onto OSCAL Assessment Results** (`observation`, `subjects`, `methods`,
`finding.related-observations`), which is how Prooflayer evidence can feed an
OSCAL consumer without reshaping.
