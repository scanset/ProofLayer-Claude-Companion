# Verification & Oversight (the CMR surface)

How an **Authorizing Official**, an auditor, a downstream consumer (SIEM/SOAR/GRC
tool), or **an AI assistant you hand a key to** reads the evidence and *verifies*
a proof — without touching the operator console and without trusting the
operator's word.

This is the **CMR** (Continuous Monitoring Record) surface: read-only, headless
in the alpha (an HTTP API, no separate UI bundle), authenticated with a **CMR
viewer key**. An admin issues the key from system-ui — see
[admin/ §tokens & keys](../admin/README.md#2-keys--webhooks-apiadmin).

> **For the AI assistant:** if the user gives you a CMR viewer key, you may call
> the `/cmr-api/*` endpoints below on their behalf to fetch data and answer
> questions. You must **not** run the product binaries or trigger scans — that's
> the operator's action. You read and verify; you don't execute.

## Authenticating

Every call carries the key as a bearer token:

```bash
CMR_KEY=plk_...                       # the CMR viewer key an admin issued
BASE=http://localhost:9090     # or the published CMR host/port
curl -H "Authorization: Bearer $CMR_KEY" "$BASE/cmr-api/summary"
```

## What you can read (all read-only)

| You want… | Endpoint |
|---|---|
| Boundary posture roll-up | `GET /cmr-api/summary` |
| Per-asset evidence (latest scan per asset×policy) | `GET /cmr-api/evidence/by-asset` |
| One asset's history — posture, state chain, findings, finding events, CTN drift | `GET /cmr-api/assets/{id}/…` |
| Compliance findings | `GET /cmr-api/findings` |
| Vulnerability findings + rollup | `GET /cmr-api/vdr/findings`, `…/vdr/summary` |
| Control rollup (evidence mapped to framework controls) | `GET /cmr-api/controls` |
| The exact policy source + check contract behind any result | `GET /cmr-api/esp-policies/…`, `…/contracts/…` |
| The transparency log (entries, inclusion proofs, checkpoints) | `GET /cmr-api/transparency/…` |

The control rollup and the "read the exact `.esp` behind a result" endpoints are
the *don't-trust-verify* surface: you see the precise logic that produced a
verdict, not just the verdict.

## Verifying a proof on demand

The differentiator. Given a result's **replay hash**:

```bash
curl -H "Authorization: Bearer $CMR_KEY" \
  "$BASE/cmr-api/verify/{replay_hash}"
```

This **reconstructs the verdict without re-running the scan** — it recompiles the
readable policy, re-projects the bound asset, and recomputes the replay hash from
the stored per-check result hashes — and returns:

- `matches` — whether the recomputed hash equals the claimed one (the producer's
  self-check),
- the reconstructed **manifest** (the readable intent + contract you can
  recompute against yourself),
- the **signature** (algorithm, signer, the detached signature + the exact bytes
  it covers, the public key, and the leaf→root certificate chain),
- the **transparency** inclusion proof (log index, tree size, root hash, audit
  path),
- a **story** layer (policy title/description, the control mapping, the asset,
  timing) for human context.

And to fetch the signer's key independently of any one attestation:

```bash
curl -H "Authorization: Bearer $CMR_KEY" \
  "$BASE/cmr-api/identity/{key_id}"        # → public key + certificate chain
```

## How far "verifiable" goes today — be honest

- ✅ **Reproducible:** everything needed to recompute the verdict is exposed. The
  hash *can* be reproduced from the served inputs.
- 🔶 **Independently verifiable:** the `matches: true` above is *our* recompute.
  A truly independent check needs a standalone open-source verifier (so the
  consumer recomputes it themselves), the served key cross-checked against the
  logged certificate, and external witnessing of the log. Those are the roadmap.

So the accurate phrasing is **"reproducible from exposed inputs, verifiable
against a trusted root"** — not yet "independently verifiable" full-stop. The
complete claim hierarchy is in
[components/transparency-and-verifiable-evidence.md](../components/transparency-and-verifiable-evidence.md).

Related: [understanding-evidence.md](../components/understanding-evidence.md),
[replay-hash.md](../components/replay-hash.md),
[surfaces.md](../components/surfaces.md).
