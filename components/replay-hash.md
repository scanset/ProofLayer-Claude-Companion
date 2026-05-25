# Replay Hash

**Status: built.** *The single most distinctive primitive in Prooflayer.*

## What it is

The replay hash is a **SHA-256 over the normalized inputs of a scan** — not over
the raw output, and not over identity. It is **deterministic** and
**identity-free**: two different hosts with the *same compliance posture*
produce the *same* replay hash. Re-run the same scan later and an unchanged
posture reproduces the same hash.

That one property does two jobs at once:

- **Drift detection** — the hash changed ⇒ the posture changed.
- **Tamper / reproducibility check** — re-run it; if the hash differs from what
  the envelope claims, something doesn't reproduce.

## Why identity-free matters

Identity (which host, which account) is deliberately **not** an input. The
inputs are the *intent and contract* of the check — schema version, policy
identity, platform, criticality, control mappings, and a hash of the collected
state — but never a hostname or asset id. Consequences:

- **Fleet dedup** — 500 identically-configured hosts collapse to one hash; you
  reason about *distinct postures*, not 500 envelopes.
- The envelope still *labels* which asset it attests about — identity lives in
  the envelope, just not in the hash.

## The hash hierarchy (three levels)

Replay hashing is hierarchical (current rollup is version 2):

```
per-CTN × per-OBJECT hash   ← the leaf
      └─ rolls up into ─▶ policy hash  (per policy: CTN object hashes + intent)
                              └─ rolls up into ─▶ envelope hash  (per scan)
```

A scoped/injected policy that fans out to N resources produces **N leaf hashes**
— one verdict and one replay hash *per resource*, not a single rolled-up
pass/fail. That granularity is what makes per-asset drift meaningful.

## How an evaluator uses it

- `GET /verify` and the evidence verify-hash endpoint look a hash up against
  stored evidence.
- The evidence reproducibility and per-CTN drift endpoints expose the
  per-CTN/per-object level.
- Run a scan twice with no change → identical replay hash. Change one setting
  on the target → the leaf for that CTN×OBJECT changes, rippling up to a new
  envelope hash.

## Don't break it

Changing what feeds the hash (e.g. remapping how an outcome is represented, or
folding identity in) silently breaks fleet dedup and cross-run comparison. The
inputs are a contract. See also
[evidence-and-ingest.md](evidence-and-ingest.md) and
[transparency-log.md](transparency-log.md) (the hash is what the log anchors).

**Deep dive:** the byte-exact canonical pre-image, the `H(x)` primitive, and the
v1/v2 rollup algorithms are in
[replay-hash-canonical-spec.md](replay-hash-canonical-spec.md) — the contract a
third-party verifier implements against.
