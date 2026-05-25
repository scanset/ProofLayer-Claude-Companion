# Transparency Log

**Status: built (single-operator; consistency proofs not yet).**

## What it is

An **append-only Merkle tree** modeled on RFC 6962 (Certificate Transparency).
Every signing identity — the in-process scanner identity, and any future signer
— is appended as a leaf with an **inclusion proof**, and the tree root is
committed periodically in a **signed checkpoint**. It lives in its own dedicated,
isolated store, and updates and deletes are blocked at the storage layer — append
is the only legal mutation. The root is checkpointed on a fixed interval.

## What it proves — and what it doesn't

It gives **real non-repudiation of issuance**: you can prove a given signing
identity / certificate existed in the log at a point in time, and verify a
specific entry's inclusion against the published root. The UI verifies inclusion
proofs **client-side** — "don't trust, verify" at the per-attestation level.

**Honest scoping for evaluators:** the alpha is **tamper-evident, not
tamper-proof**. It's a single operator's log; there are **no consistency proofs
and no external witnessing yet**. So:

- ✅ "Here is cryptographic proof this attestation's signing cert is in the log."
- ❌ "The operator cannot have rewritten history." (Not claimable yet — the
  gap-closers, consistency-proof primitives, are bounded future work.)

Say *tamper-evident*. Don't oversell it.

## How it connects to the rest

- A scan is signed (see [pki-and-identity.md](pki-and-identity.md)); the
  signer's certificate is what gets logged.
- The envelope carries its inclusion proof (log index, tree size, root hash,
  audit path).
- Browse it: `/api/transparency/*` (system-ui) and `/cmr-api/transparency/*`
  (AO) expose tree summary, entries, per-entry envelopes, `proof/{index}`, and
  checkpoints.

## Evaluator's view

Run a scan, open the Transparency page, find the new entry, and verify its
inclusion proof. Then note the checkpoint that commits the tree root. That chain
— signed envelope → logged identity → inclusion proof → signed checkpoint — is
the auditable spine of the product.

> One operational trap (since fixed): if evidence storage rejects an outcome
> value it doesn't expect, the *whole* scan ingest can roll back and the
> envelope's signing activity never reaches the log — making the page look
> empty. See [ops/](../ops/README.md#5-troubleshooting).

---

**Deep dive:** the leaf/node hashing, inclusion-proof and checkpoint structure,
the end-to-end verification procedure, and the honest "reproducible vs
independently verifiable" claim hierarchy are in
[transparency-and-verifiable-evidence.md](transparency-and-verifiable-evidence.md).
