# Understanding Evidence — The Anatomy of a Proof

**Status: built.** Every scan produces one of these. This page explains what a
piece of evidence *is*, why it's a **proof** and not just a finding, and how to
read one.

## Finding vs. proof

A normal scanner hands you a **finding**: *"SSH root login is permitted on
web-01."* You have to trust that the scanner looked correctly, and the result is
a dead artifact the moment you save it.

Prooflayer hands you a **proof**: the same verdict, plus everything needed to
*independently believe it* — the exact readable check that produced it, a
deterministic fingerprint of that check, a signature saying who ran it, a
transparency-log record of when, and the command to re-observe the state
yourself. The verdict is the small part; the *provability* is the product.

> *Wiz makes findings; Prooflayer makes proofs.*

## What a piece of evidence contains

One scan produces one **signed evidence envelope**. Conceptually it carries:

| Layer | What it is | What it answers |
|---|---|---|
| **Verdict** | Per-policy outcome (`pass` / `fail` / `error`) and the per-check, per-object results underneath it. | *What did the check conclude?* |
| **Replay hash** | A deterministic fingerprint over the check's **intent + contract + outcome**. Same observed posture → same hash. | *Is this exactly this check and this result?* (re-runnable, tamper-evident) |
| **Signature** | A cryptographic signature by the scanner's identity, with its certificate chain back to a trusted root. | *Who attested this?* |
| **Transparency record** | An append-only Merkle-log entry + inclusion proof for the signing event. | *When, and provably-logged?* |
| **Control mapping** | The framework controls the policy maps to (FedRAMP 20x KSI, NIST 800-53/800-171). | *Which compliance requirement does this satisfy?* |
| **Reproduction detail** | For each result, the exact command the check ran on the target. | *How do I re-observe this myself?* |

Importantly, the parts you can publish to *prove* the verdict don't leak the
scanned system's raw data — the replay-hash inputs carry pass/fail structure,
not the underlying values. See
[transparency-and-verifiable-evidence.md](transparency-and-verifiable-evidence.md).

## How to read one

In system-ui (per-asset evidence) or over the API, an envelope gives you:

1. **Posture** — the headline `pass` / `fail` / `error` / `unknown` for the
   asset against that policy.
2. **Findings** — the failing checks, each with **expected vs. actual** and the
   **reproduction command** ([findings-and-remediation.md](findings-and-remediation.md)).
3. **The replay hash** — the fingerprint you (or an auditor) can recompute. An
   unchanged target re-scanned reproduces the same hash; a different hash means
   *something changed* — drift or tampering.
4. **The signature + transparency entry** — verify who signed it and that it's
   in the log.

## Why this matters

Because the evidence is **reproducible, attributable, tamper-evident, and
control-mapped**, the *same* envelope serves the operator (triage), the AO
(oversight), and a downstream consumer (a SIEM/SOAR, a GRC tool) — nobody
re-keys it, and anyone can check it. That single reusable, verifiable artifact
is the "make proof once, use it anywhere" thesis.

Go deeper: [replay-hash.md](replay-hash.md) (the fingerprint),
[transparency-and-verifiable-evidence.md](transparency-and-verifiable-evidence.md)
(how to verify end-to-end), [evidence-and-ingest.md](evidence-and-ingest.md)
(the envelope + how scans land), [pki-and-identity.md](pki-and-identity.md) (the
signing identity).
