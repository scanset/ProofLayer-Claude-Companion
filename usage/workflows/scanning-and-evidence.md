# Workflow 4 — Scan & Read Evidence

With assets linked to policies, you scan — and a scan produces the **proof**: a
signed, replay-hashable, transparency-logged envelope mapped to controls. This
page covers triggering scans and reading what comes back (posture, drift,
findings, the per-asset proof timeline).

> Where: **Asset Detail** (per-asset scanning + evidence), the **Assets** page
> (bulk scan), and the **Posture Scan** page (fleet runs). Concept of the proof:
> [../../components/evidence-and-ingest.md](../../components/evidence-and-ingest.md),
> [../../components/replay-hash.md](../../components/replay-hash.md).

---

## Triggering a scan

| You want to… | Do this |
|---|---|
| Scan one asset against all its active links | **Asset Detail → pick a credential → "Scan all"** |
| Scan one asset against selected links | Asset Detail → select policy rows → link-actions → **Scan** |
| Scan many assets at once | **Assets page → select assets → scan** (parallel batch) |
| Scan the whole fleet (with a preview first) | the **Posture Scan** page — see below |
| Sanity-check one policy on one asset (no persistence) | a **test-scan** — runs and returns the envelope inline, nothing stored |

Each dispatch: resolves the credential → builds the channel → runs the policy's
checks through the engine → **signs with the in-process scanner identity** →
**appends to the transparency log** → **persists the evidence**. Only **active**
links scan; paused/archived/pending are skipped (with a count). A scan that
fans out via [scoped injection](../../esp/injection-and-scoped-injection.md)
produces a per-resource verdict for each matching resource.

> First scan with no cloud creds? Use the local channel against the container
> host — see the Tier-0 quickstart in [../../test_fixtures/](../../test_fixtures/README.md).

---

## Posture Scan — the fleet run

The **Posture Scan** page dispatches many scans in one call — the "scan
everything that's ready" button for an evaluation. It's the broad counterpart to
per-asset scanning, with a **dry-run preview** so you can see exactly what would
fire before anything does.

**What it lists.** Only assets with **at least one active policy link** are
eligible (no links → nothing to run). A *"Hide assets that aren't scan-ready"*
toggle (on by default) further hides assets missing what a scan needs — a bound
credential for a host, or a provider id for a cloud asset — and a counter shows
`N eligible / M total`. Each row shows the asset, type, its **active policy
count**, the bound credential, last-seen, and a scan-ready ✓; the list is
searchable and sortable.

**Scope.** Select rows to scan just those; **leave everything unselected to run
every visible (eligible) asset.** The selection bar tells you how many policies
will dispatch.

**Preview, then run.** The **Dry run** box is **checked by default** — the
button reads **Preview** and returns a *dispatch preview*: assets processed,
policies planned, the planned dispatch per asset, and any **skipped** assets with
the reason. Nothing is signed, logged, or persisted in a dry run. Uncheck Dry
run and the button becomes **Run scan**: a real parallel batch dispatch
(`POST /api/inventory/scan-now/batch`) that reports per-asset outcomes
(attempted / pass / fail / duration), the succeeded/failed/skipped totals, and
total time. Each dispatched scan is a normal signed, transparency-logged,
persisted proof.

> If the page is empty it tells you why: *"No assets in inventory — run discovery
> first"* or *"No assets have policies linked — run auto-link first."* That's the
> **discover → auto-link → posture scan** path.

---

## Reading the evidence (Asset Detail)

An asset's detail page is the operator's evidence cockpit. The sections:

- **Recent scan runs** — one row per dispatch: trigger (`manual`/`scheduled`/
  `replay`/…), status, time. Click a run to open the **envelope**; **Re-run**
  replays the exact input tuple (a re-run with unchanged posture reproduces the
  same replay hash).
- **Open findings** — the failing checks, each with the reproduction detail so
  you can see *why* it failed and how to confirm.
- **Drift since prior scan** — a table of CTN×object whose hash changed (from →
  to), with timestamps; click through to the full hash-chain timeline. "Drift"
  here means the posture hash changed — see
  [../../components/posture-and-drift.md](../../components/posture-and-drift.md).
- **State chain** — the per-(asset, policy) replay-hash timeline: how posture
  evolved over time, each point a signed, reproducible state, each link chained
  to the previous by hash. Full detail:
  [../../components/state-chain.md](../../components/state-chain.md).

The headline per asset is **current posture** (`pass` / `fail` / `error` /
`unknown`), backed by the append-only **posture-event ledger**
(`first_seen` / `drift` / `reversion` / `stable`).

---

## Host enrichment (optional, before scanning hosts)

For host assets, **Asset Detail → Enumerate** runs an OS inventory over SSH
(pick the OS profile + credential) to populate installed software + services —
useful before vulnerability-oriented checks. Pick the right OS profile; a wrong
one fails because the package manager isn't present.

---

## Verifying the proof

Any result can be verified, not just trusted:

- **Replay hash** — re-run an unchanged target → identical hash. The `/verify`
  utility (and the evidence verify-hash query) look a hash up against stored
  evidence.
- **Signature + chain** — the envelope carries the signer's certificate chain
  back to the root.
- **Transparency log** — the **Transparency** page shows the tree, entries,
  inclusion proofs, and signed checkpoints; proofs verify client-side.

The full "reproducible vs independently verifiable" story is in
[../../components/transparency-and-verifiable-evidence.md](../../components/transparency-and-verifiable-evidence.md).
The same evidence is what the read-only **CMR** oversight surface exposes to an
Authorizing Official.

Next: keep it running on a cadence → [scheduling.md](scheduling.md).
