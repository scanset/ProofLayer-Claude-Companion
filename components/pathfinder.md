# Pathfinder

**Status: built (V2 — focus-asset risk-neighborhood graph). Attack-*path*
finding, exploit/ATT&CK-derived edges, and AI narration are the planned next
step.** Pathfinder ships in the alpha as a read-only graph view under the
vulnerability (VDR) section of system-ui.

## The idea

A **graph projection** over the inventory + findings + signed-evidence stack. It
turns that data into a visual map: assets are **nodes**, the relationships
discovered between them are **edges**, and each node carries its open-finding
risk. The wedge:

> *BloodHound showed you what AD lets attackers do. Pathfinder shows you what
> your **compliance posture** lets them do — with the evidence to prove every
> node's risk is real, signed, and replayable.*

The differentiator over a pure attack-graph tool is the product's core property:
node risk isn't *modeled*, it's **proven** — every finding on a node traces back
to a signed, replayable scan in the [transparency log](transparency-log.md). The
graph is a *projection* over evidence Prooflayer already produces, not a new
source of truth.

## What it does today (V2)

- **Focus + neighborhood.** You pick a **focus asset**; Pathfinder walks the
  asset graph outward in both directions to a chosen **depth** (1–5 hops) and
  draws the surrounding neighborhood.
- **Edges are discovered linkage.** The connections are the relationships
  discovery already recorded between assets (e.g. *contains* / *references* —
  a subscription contains a resource group, a cluster contains a node). Edge
  labels are shown verbatim.
- **Nodes carry real risk.** Each asset is hydrated at request time with its
  open-finding counts — critical / high / total — and a KEV flag, all sourced
  from signed scan evidence.
- **Risk coloring + one-hop spread.** A node is colored by its own severity
  (red for KEV/critical, orange for high, amber for low/medium). Risk "spreads"
  one hop: a neighbor of a serious node gets an at-risk tint, so you can see
  blast radius — *what sits next to the dangerous thing*.

In short: a **risk-neighborhood / blast-radius view** grounded in discovered
topology and evidence-backed findings.

## What's planned next (not in the alpha)

- **Source → target attack paths** — ask "how could an attacker get from A to
  B," not just "what's around A." (The path-finding parameters exist but aren't
  wired yet.)
- **Exploit / ATT&CK edges** — edges *derived from findings* (an exploitable CVE,
  an over-broad grant) labeled with MITRE ATT&CK techniques, layered on top of
  the structural edges.
- **AI narration** — technique mapping, edge inference, crown-jewel scoring, and
  plain-language path narration.

If asked what's real today: *the focus-asset risk-neighborhood graph with
evidence-backed node risk and one-hop spread is built; attack-path finding and
the AI/exploit-edge layers are the roadmap.*

## How to use it

system-ui → **VDR → Pathfinder**: pick a focus asset, set the depth, and read
the neighborhood — node color is that asset's own finding severity, tinted
neighbors are one hop from something serious. See the
[Pathfinder workflow](../usage/workflows/pathfinder.md).

Builds on: [inventory.md](inventory.md) (the asset graph),
[vulnerability-vdr.md](vulnerability-vdr.md) and
[findings-and-remediation.md](findings-and-remediation.md) (node risk),
[evidence-and-ingest.md](evidence-and-ingest.md),
[transparency-log.md](transparency-log.md).
