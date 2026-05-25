# Findings & Remediation

**Status: built.** Findings flow automatically from signed scans; an operator
records remediation decisions; the lifecycle updates itself on every rescan.

## What a finding is

A **finding** is a specific thing that needs attention, derived from a signed
scan — never hand-entered. There are two kinds:

| Kind | Comes from | Example |
|---|---|---|
| **Compliance finding** | A **failed policy check** in a scan. One per failing check (per object). | "SSH root login is permitted" — control IA-2 fails on `web-01`. |
| **Vulnerability finding (VDR)** | The **CVE projection** — scan state matched against detection signatures in the catalog. One per CVE × asset. | "CVE-2024-XXXX affects `db-01` (KEV, critical)." |

Both carry the context to act on and to *prove*: the affected asset, severity,
the **expected vs. actual** state (for compliance findings), the controls it
maps to, and — critically — the **reproduction command** so anyone can re-observe
the same state. Each finding traces back to the signed envelope that produced it.

## The lifecycle — findings track themselves

This is the part that makes findings a *living* record rather than a static
list. Each finding has a status, and every change is appended to a **finding
event ledger** (the same append-only discipline as the posture ledger):

```
        ┌─────────────── rescan still fails ───────────────┐
        ▼                                                    │
   first_seen ──▶ open ──── rescan passes ────▶ resolved ────┘
                    │                               │
            operator decision               regression on a
            (accept / false-positive)        later scan
                    │                               │
                    ▼                               ▼
              decided (tracked)                 reopened
```

- **first_seen** — a scan surfaces the issue for the first time.
- **resolved** — a later scan of the same target *passes*; the finding closes on
  its own, backed by the passing evidence. No human marks it fixed.
- **reopened** — a still-later scan regresses; the finding comes back, with the
  full before/after trail intact.
- **decided** — the operator records a **remediation decision** (see below).

Because every transition is evidence-backed and timestamped, the ledger answers
"when did this break, when was it fixed, did it come back?" without anyone
re-keying status.

## Remediation decisions

For a finding you won't (or can't) immediately fix, the operator **records a
decision** instead of leaving it ambiguous — an inline form on the finding (the
same form on the Vulnerabilities/CVE page and the Misconfigurations/compliance
page). Five decision kinds:

| Decision | Meaning | Notes |
|---|---|---|
| **Remediation planned** | a fix is scheduled | supports a **target date** |
| **Mitigation in place** | a compensating control reduces the risk | supports a **target date** |
| **Remediated / verified** | fixed and confirmed | usually set automatically when a rescan passes; recordable explicitly |
| **Accept risk** | acknowledged, not fixing now | **rationale required** |
| **False positive** | the detection doesn't apply here | **rationale required** |

- **Rationale** (a markdown note) is the **audit artifact** — encouraged on every
  decision, and **mandatory** for *Accept risk* and *False positive* (the form
  won't save without it).
- **Target date** appears only for the plan-shaped decisions (*Remediation
  planned*, *Mitigation in place*).
- Recording a decision **flips the finding's status** and is an UPSERT — you can
  revise it later. The decision is part of the finding's durable record.
- **Bulk decisions** — select many findings and apply one decision atomically
  (all-or-nothing) in a single step.

Endpoints: a CVE/VDR finding takes a decision at
`POST /api/inventory/vdr/findings/{id}/decision`; a compliance finding is
decided via `…/vdr/mark-misconfig` (and `…/mark-misconfig/bulk`), which projects
the finding's VDR counterpart and records the decision together. You can filter
the findings list by recorded decision (any / undecided / a specific kind).

Decisions travel with the evidence and are visible to oversight (the AO via
CMR), so the "what are you doing about this" answer is attached to the finding
itself — not kept in a side spreadsheet.

## The "automatic POA&M" idea (framed honestly)

A traditional **POA&M** (Plan of Action & Milestones) is a static document an
auditor maintains by hand: open items, owners, target dates, status — and it
goes stale the moment the system changes. Prooflayer's findings are the
**continuous, evidence-backed equivalent of that line-item tracking**: an item
opens when a check fails, closes when a rescan proves it fixed, reopens on
regression, and carries a recorded decision when accepted — all driven by signed
scans, not manual edits.

> **Be precise about scope:** the alpha does **not** ship a POA&M *document
> manager* or the GRC authoring workflow around it (that's a partner concern —
> see [surfaces.md](surfaces.md)). What it ships is the live finding lifecycle
> above, which a GRC tool can consume. Describe it as "the evidence-backed
> tracking a POA&M would sit on top of," not "an automatic POA&M feature."

## How to reach it

- **Operator (system-ui):** browse and triage findings, record remediation
  decisions — see the [vulnerability-triage workflow](../usage/workflows/vulnerability-triage.md)
  and [scan & read evidence](../usage/workflows/scanning-and-evidence.md).
- **Oversight (CMR):** the read-only mirror of findings + the per-asset finding
  event ledger — see [verification & oversight](../usage/verification-and-oversight.md).

Related: [vulnerability-vdr.md](vulnerability-vdr.md),
[understanding-evidence.md](understanding-evidence.md),
[posture-and-drift.md](posture-and-drift.md).
