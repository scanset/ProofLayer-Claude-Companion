# Operator Workflows

How to actually *use* Prooflayer from the **system-ui** operator console — the
concrete click-paths for the core actions, in the order you do them. The
[surfaces overview](../README.md) explains *what* system-ui is; these pages are
the *how*.

## The operator spine

Everything an operator does hangs off one loop:

```
1. Add a credential ──▶ 2. Discover assets ──▶ 3. Auto-link policies ──▶ 4. Verify scoping
   Admin → Credentials      Discover page          Discover page button     Inventory Assignments
                                                                                   │
        7. Schedule  ◀── 6. Read evidence / posture / drift  ◀── 5. Scan ◀─────────┘
        (per link)          Asset detail                          scan-now / batch
```

A credential is the reusable secret; discovery turns it into assets; auto-link
binds the right policies to those assets; a scan produces signed, control-mapped
evidence; schedules keep it running.

## The pages

| # | Workflow | Page | What you do |
|---|---|---|---|
| 1 | **Set up credentials** | [credentials.md](credentials.md) | Add the secret Prooflayer authenticates as (12 kinds). |
| 2 | **Discover assets** | [discovery.md](discovery.md) | Enumerate everything a credential can see into the inventory. |
| 3 | **Auto-link & assign policies** | [auto-link-and-assignment.md](auto-link-and-assignment.md) | Bind policies to assets — one-click reconcile, or manual assignment — **and why each policy applies**. |
| 4 | **Scan & read evidence** | [scanning-and-evidence.md](scanning-and-evidence.md) | Run scans, then read posture, drift, findings, and the per-asset proof timeline. |
| 5 | **Schedule** | [scheduling.md](scheduling.md) | Put a cadence on each asset↔policy link. |
| 6 | **Vulnerability triage** | [vulnerability-triage.md](vulnerability-triage.md) | Browse the CVE catalog, triage VDR findings, record remediation decisions. |
| 7 | **Pathfinder (risk neighborhood)** | [pathfinder.md](pathfinder.md) | Visualize where risk concentrates across assets and what sits next to it. |

> Workflows 6–7 are **downstream of a scan** — they read and act on the findings
> a scan produced, rather than being part of the setup→scan spine above.

## Two things to keep straight

- **A credential ≠ an asset ≠ a binding.** One credential reaches many assets; a
  binding (asset↔policy link) is what actually gets scanned. Concept:
  [../../components/inventory.md](../../components/inventory.md).
- **Policies fan out at scan time.** You bind *one* policy to *one* asset (or
  auto-link in bulk); **scoped injection** expands it to every matching resource
  when the scan dispatches — so binding a policy to a subscription scans every
  resource under it. Concept:
  [../../esp/injection-and-scoped-injection.md](../../esp/injection-and-scoped-injection.md).

> **Where to act:** all of this is the operator (system-ui) surface. The
> read-only oversight (CMR) surface doesn't create credentials, link policies, or
> trigger scans — it reads the resulting evidence. See
> [../../components/surfaces.md](../../components/surfaces.md).
