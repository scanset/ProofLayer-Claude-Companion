# Workflow 7 — Pathfinder (Risk Neighborhood)

How to use the **Pathfinder** graph to see where risk concentrates across your
assets and what sits next to the dangerous things. Concept + roadmap:
[components/pathfinder.md](../../components/pathfinder.md).

> Where: **system-ui → VDR → Pathfinder**. Read-only — Pathfinder visualizes the
> inventory + findings you already produced; it doesn't change anything.

## What it shows

Pathfinder draws a **graph** of your assets:

- **Nodes** are assets, each carrying its **open-finding risk** (critical / high
  / total, plus a KEV flag) sourced from signed scan evidence.
- **Edges** are the relationships discovery recorded between assets (e.g. a
  subscription *contains* a resource group; a cluster *contains* a node). Labels
  are shown verbatim.
- **Color = risk.** A node is colored by its own severity — red for KEV or
  critical findings, orange for high, amber for low/medium.
- **One-hop spread.** Risk "bleeds" one hop: a neighbor of a serious node gets
  an at-risk tint, so you can see **blast radius** — what an attacker reaching
  the dangerous node could touch next.

## Using it

1. **Pick a focus asset.** The graph centers on it.
2. **Set the depth** (1–5 hops). Pathfinder walks outward from the focus in both
   directions to that many hops and draws the surrounding neighborhood.
3. **Read the picture.** The focus node is ringed; strongly-colored nodes have
   their own serious findings; tinted nodes are one hop from something serious.
   Follow the edges to understand *why* two assets are connected.
4. **Drill back to evidence.** A node's risk traces to its findings — jump to the
   asset's findings and the signed scan that produced them
   ([vulnerability triage](vulnerability-triage.md),
   [findings & remediation](../../components/findings-and-remediation.md)).

## What it does *not* do yet

- **No source→target attack paths.** Today it answers "what's around this asset
  and where's the risk," not "trace a route from A to B." Path-finding is roadmap.
- **No exploit/ATT&CK-derived edges or AI narration.** Edges are the discovered
  structural linkage; the finding-derived exploit edges and technique labels are
  the planned next layer.

So describe it honestly: a **built, evidence-backed risk-neighborhood view** —
the attack-*path* analysis is coming, not shipped.

Related: [components/pathfinder.md](../../components/pathfinder.md),
[inventory.md](../../components/inventory.md) (the asset graph the edges come
from), [vulnerability-vdr.md](../../components/vulnerability-vdr.md).
