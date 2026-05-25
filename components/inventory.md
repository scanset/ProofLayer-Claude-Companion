# Inventory — Credential, Asset, Channel Binding

**Status: built (credentials + assets + linking; bindings table maturing).**

## The three-concept model

Prooflayer's inventory has **three** distinct concepts, not two. Separating the
asset from how you reach it is what enables multi-channel assets, failover, and
credential rotation without touching the asset record.

| Concept | What it is | Lifecycle |
|---|---|---|
| **Credential** | Reusable secret material — an SSH key, an Azure SPN, an AWS role, a WinRM password. A connection profile, not a target. | Rotated on its own cadence; referenced by many assets. |
| **Asset** | The thing being scanned — a Linux VM, an AWS account, a K8s cluster, an M365 tenant. The subject of an envelope. | Discovered once, persists, tracks identity over time. |
| **Channel binding** | How to reach a specific asset — the asset, a channel kind, its config, and the credential references it needs. | Edited when network/creds change. One asset can have several (primary SSM, fallback SSH). |

Why three: one SSH key rotates and 40 VMs keep working (the key is its own
record); one asset is reachable by SSM-primary + SSH-fallback (a single asset can
carry several bindings); one bastion binding can reference two credentials — the
tunnel SPN *and* the inner SSH key (a binding can reference many credentials).

## Credentials

Stored as **least-privilege-scoped plaintext** secret material. There is no
app-layer encryption — security comes from host disk encryption, least-privilege
access scoping that separates who may write a credential from who may read it on
the dispatch path, and loopback-only reachability (a deliberate architecture
decision). The 12 kinds are
`aws_access_key`, `aws_role`, `azure_spn`, `azure_spn_cert`,
`m365_delegated_refresh`, `gcp_sa_key`, `ssh_key`, `winrm_password`,
`github_pat`, `kube_config`, `local`, `network_target` — each documented in
[../usage/credentials/](../usage/credentials/README.md). Non-secret display hints
(region, tenant) are kept separately so they are safe to show in the UI.

There are **no ambient-credential variants** — every account, including the one
Prooflayer runs in, has its own explicit record. The VM instance role is
bootstrap-only.

## Assets

Discovered (see [discovery.md](discovery.md)) or hand-created. Each carries an
asset type, a provider id, free-form metadata, graph edges to its parents (which
injection walks), and its current posture with the time it was last updated.
Assets are soft-deleted, not hard-deleted.

## The asset graph — link taxonomy

Discovery is the **single writer** of the graph; nothing else mutates it. It
records not just assets but how they relate, in **two layers**.

### Structural edges (the scope-walked graph)

Stored on each asset as `parents[]` / `children[]` of `{asset_id, relation}`,
written **bidirectionally** — name A a parent of B with relation R and the mirror
(B a child of A with R) lands in the same transaction, so the graph is walkable
from either end. These are the edges scope resolution walks. The `relation` is
**open-vocab** (no DB constraint); the conventional set, with whether the scope
walk follows it by default:

| Relation | Walk-eligible? | Meaning / example |
|---|---|---|
| **`contains`** | **Yes (default)** | hierarchy — subscription→RG→VM, VPC→subnet, tenant→user, host→systemd unit |
| **`member_of`** | **Yes (default)** | membership — user→group (so "scan all users in this group" works) |
| `references` | opt-in | cross-resource ref — NSG→subnet, EC2→security group, RoleBinding→Role |
| `attached_to` | opt-in | attachment (a variant of `references`) — EIP→instance, NIC→VM, disk→VM |
| `alias_of` | opt-in | same real thing on two planes — `M365::ManagedDevice` ↔ the Azure VM that *is* that device (one box, two enrollments) |
| `installs` | opt-in | host → a **deduped** `Software::Package` node (`name@version`, shared across hosts). SBOM / vuln **blast-radius** edge — deliberately *not* default-walked, so CVE scanning stays anchored on the host |
| `peers_with` | opt-in | VPC ↔ VPC peering |

"Walk-eligible" is the **default** scope set (`contains` + `member_of`). A policy
opts into walking any other relation by naming it in its placeholder's `link`
directive. (Single-hop field lookups — "linked" fills — may follow *any* relation,
since they're one hop, not a subtree walk.) `alias_of` is the quietly powerful
one: it stitches an identity two providers each report independently into one
asset, keeping the graph connected *across* clouds.

### Linkage layer (semantic edges, for Pathfinder)

Beyond the structural edges, discovery materializes a richer set of **semantic
edges** (a seeded `linkage_registry`) written under `metadata.linkage.*` rather
than into `parents/children`. **None are scope-walked** — they exist for
attack-path traversal and blast-radius, e.g. `grants` / `binds` / `uses` (K8s
RBAC + workloads), `deploys_to` / `built_by` / `produces` / `describes` (SDLC →
runtime → SBOM), `trusts` / `federates_to` / `backs` / `owns` (identity),
`assigned_to`, `derived_from` (base images). Containment-shaped linkage keys
(`in_namespace`, `in_subnet`, …) collapse back onto the structural
`contains`/`attached_to`/`references` rows — the same relations expressed as
linkage keys, not new verbs.

### One graph, one writer, two consumers

Getting the relations right at discovery time pays off because **two subsystems
read the same graph** (and discovery is the only writer):

1. **Scoped injection (scan scope).** A bound policy fans out by **walking the
   structural graph** — default `contains` + `member_of`, dedup-safe — from the
   bound asset to every `target`-typed descendant, one per-resource verdict each.
   Bind one storage-TLS policy to a subscription → scan every storage account
   beneath it. The taxonomy is the rails the walk runs on. See
   [../esp/injection-and-scoped-injection.md](../esp/injection-and-scoped-injection.md).
2. **Pathfinder (risk projection).** The same graph — structural edges *plus* the
   linkage layer — is projected into nodes and labeled edges; a focus-asset
   **neighborhood** walk expands outward in both directions to a chosen depth, and
   open-finding risk propagates along the edges. This is where the non-walked
   relations (`installs`, `grants`, `trusts`, …) earn their keep — they're the
   blast-radius and attack-path lines — and the seam where a future *exploit*-edge
   layer plugs in. See [pathfinder.md](pathfinder.md).

So the link taxonomy isn't bookkeeping — it's the single shared structure that
the relationship view *is*, that scan fan-out walks, and that risk projection
draws.

## Linking is how scanning is driven

A policy is **bound to an asset** with a status of active, paused, or archived.
That binding — not the policy text — determines scope; at dispatch the server
injects the concrete targets (see
[injection-and-scoped-injection.md](../esp/injection-and-scoped-injection.md)). Each
dispatch records the full input tuple — the asset, policy, credential, the policy
content fingerprint, the scanner identity, the trigger, and any parent run — so
any run can be **replayed** deterministically.

Operate all of this from [admin/](../admin/README.md#3-credential-governance-apiinventorycredentials)
and [usage/](../usage/README.md).
