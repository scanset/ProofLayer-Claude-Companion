# The State Chain

**Status: built.** The per-(asset, policy) timeline of signed scans, each link
chained to the one before it by replay hash — the "how did this asset's posture
get to where it is" view.

## What it is

For a given **asset + policy**, every scan produces one signed
[evidence envelope](understanding-evidence.md). The **state chain** is those
envelopes laid out in time order, each one **linked to its predecessor**:

```
   scan #1            scan #2            scan #3            scan #4
   hash A             hash A             hash B             hash A
   (first_seen)       (stable)           (drift)            (reversion)
      ●─────────────────●─────────────────●─────────────────●
                        prev = A           prev = A           prev = B
```

Each link in the chain carries:

- its **replay hash** and the **previous** envelope's replay hash (so you can see
  exactly when the hash — and therefore the posture — changed),
- the **outcome** at that point (`pass` / `fail` / `error` / `unknown`),
- **when** the scan completed (and when the previous one did), and
- the **triggering asset** — which binding set this scan off (see scoped
  injection below).

Because the [replay hash](replay-hash.md) is deterministic and identity-free, the
chain reads at a glance: **same hash = nothing changed; new hash = drift; a
hash you've seen before = reversion.** Every link is a signed, replayable proof
— so the chain isn't a log of *claims*, it's a chain of *verifiable states*.

## State chain vs. the posture ledger

They're two views of the same history — keep them straight:

| | Granularity | Answers |
|---|---|---|
| **State chain** | per **(asset, policy)** — the envelope timeline | *"Show me this policy's result on this asset over time, hash-linked."* |
| **[Posture-event ledger](posture-and-drift.md)** | per **host** — classified transitions | *"first_seen / drift / reversion / stable — when did posture change?"* |

The ledger classifies *what kind* of change happened; the state chain is the
underlying hash-linked sequence the classification is derived from.

## Scoped injection: the triggering asset

One policy bound to a parent asset (say, a subscription or a cluster) fans out at
scan time to every matching resource under it — see
[scoped injection](../esp/injection-and-scoped-injection.md). So an envelope in a
*resource's* state chain records the **triggering asset** (the bound parent whose
scan produced it). That's how you trace a per-resource result back to the binding
that caused the scan.

## Drilling in

A state-chain link isn't a dead end — expand any envelope to its **per-check,
per-object verdicts** (the CTN results inside that scan), so you can go from
"posture changed on scan #3" down to "*which specific check* flipped, on *which
object*." Pair it with **per-CTN drift** to see exactly which check's hash moved
between two scans.

## How to read it

- **Operator (system-ui):** the asset detail page renders the state chain as a
  timeline; `/api/inventory/evidence/state-chain` (and `…/posture-history`,
  `…/ctn-drift`) back it.
- **Oversight (CMR):** `GET /cmr-api/assets/{id}/state-chain` (filterable by
  policy) — the read-only mirror; see
  [verification & oversight](../usage/verification-and-oversight.md).

Related: [replay-hash.md](replay-hash.md),
[posture-and-drift.md](posture-and-drift.md),
[understanding-evidence.md](understanding-evidence.md),
[findings-and-remediation.md](findings-and-remediation.md).
