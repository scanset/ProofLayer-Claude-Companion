# Posture & Drift

**Status: built.** *The "posture as state, not posture through evidence" idea.*

## Posture as state

Prooflayer sells **posture as state** — the cryptographic chain proves the state
*was X at time T*; the evidence is *how you get there*. Don't conflate them. The
headline value is each asset's **current posture**
(`pass | fail | error | unknown`), paired with the time it was last updated. Note
the fourth value: `unknown` is a real ESP outcome (the engine's default) — the
storage and rollups must accommodate it, not collapse it (see
[transparency-log.md](transparency-log.md) for the ingest trap this caused).

## The posture-event ledger

Posture transitions are recorded in an **append-only ledger** per host. Each
scan appends one event:

| Event type | Meaning |
|---|---|
| `first_seen` | the first posture event ever recorded for this host |
| `drift` | posture changed to a state **never seen before** for this host |
| `reversion` | posture changed **back** to a previously-seen state |
| `stable` | posture unchanged from the last scan |

This ledger is the canonical word-sense of "drift" — keep it.

## The three word-senses of "drift" (don't overload)

| Context | Meaning | Status |
|---|---|---|
| the ledger's `drift` event | a posture change to a never-before-seen hash | **canonical — keep** |
| a re-scan triggered by `posture_change` | a posture event re-fired this re-scan | renamed *from* `drift` to disambiguate |
| marketing "detect compliance drift" | customer-facing copy | OK in pitches, avoid in code/specs |

The mechanism underneath is the [replay hash](replay-hash.md): posture "changed"
precisely when the hash changed. Because the hash is identity-free, the *same*
drift on two identical hosts is recognized as the same posture.

## Scan triggers

Each run records *why* it happened: `scheduled`, `manual`, `replay` (re-dispatch
of a parent run), and `posture_change` (a posture event re-fired it).
Combined with the captured input tuple, any run is deterministically
**replayable** — see [inventory.md](inventory.md).

## How an evaluator sees it

Per asset: `current_posture` + the event ledger
(`/api/inventory/evidence/posture-history`, `…/state-chain`), and per-CTN drift
(`…/ctn-drift`). The story to tell: *here is the asset's posture today, here is
every time it changed, and here is the signed, replayable proof of each state.*

> The ledger classifies *what kind* of change happened; the
> [**state chain**](state-chain.md) is the underlying hash-linked timeline of
> signed scans those classifications come from — read it for the per-(asset,
> policy) "how did we get here" view.
