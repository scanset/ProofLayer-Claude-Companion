# Workflow 5 — Scheduling

Continuous compliance means scans run on a cadence, not just when you click.
Schedules live **on the asset↔policy link** — each binding can have its own
interval — and the **Schedules** page is the fleet-wide view of all of them.

> Where: set a cadence on **Asset Detail** (per link); manage all of them on the
> **Schedules** page.

---

## Setting a cadence

A schedule is attached to a specific **asset↔policy link**, from that link's
**Schedule** cell on **Asset Detail**:

1. Find the linked policy on the asset. Only **active** links can be scheduled —
   a paused or archived link shows `—` instead of a schedule control.
2. Set an **interval** — presets are 15 min / hourly / every 6 h / daily /
   weekly, or pick **Custom…** for an arbitrary interval (minimum **60 s**).
3. Choose the **credential** the scheduled scan will use. This is **required** —
   Save stays disabled until a credential is selected.
4. Save (`PUT /api/inventory/asset-policies/{asset}/{policy}/schedule`). The link
   now fires on that cadence; the scheduler picks up due links and dispatches
   them like a manual scan (signed, logged, persisted).

A link with no schedule simply never fires on its own — you scan it manually.

---

## The Schedules page (fleet view)

Opens to *"per-link cadences across all assets, sorted by next-fire so upcoming
work is at the top."* Summary tiles show **Total / Paused / Overdue / Last
failed**, and the table lists every scheduled link:

| Column | Shows |
|---|---|
| Asset | → the asset's detail page |
| Policy | → the policy (id + title) |
| Cadence | the interval (or a "paused" tag) |
| Next | relative time to next fire (or "—" if paused; flagged when overdue) |
| Last | last run's time + status (or "never"), with the error if it failed |
| Credential | the bound credential (flagged red as "missing" if it was deleted) |
| Actions | **Pause / Resume**, **Clear** |

From here you can:

- **Pause / Resume** a schedule — stops/restarts the countdown without touching
  the link.
- **Clear** a schedule — removes the cadence only. Confirmation makes the point
  explicit: *"the link itself stays linked."* You're removing the timer, not
  unlinking the policy.

---

## How it fits

- A scheduled run is a normal scan — same dispatch, same signed envelope, same
  transparency-log entry (see [scanning-and-evidence.md](scanning-and-evidence.md)).
- Schedules respect link status: a **paused** or **archived** link won't fire
  even if it has a cadence.
- Re-running auto-link or re-discovering doesn't disturb existing schedules; they
  stay on their links.

That closes the loop: **credential → discover → auto-link → scan → evidence →
schedule**, and the schedule keeps the evidence current.
