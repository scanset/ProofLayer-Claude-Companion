# Workflow 3 — Auto-Link & Assign Policies

This is where you decide **what gets checked on what**. A scan only happens
against an **asset↔policy link** (a "binding"). You create those links one of two
ways: **auto-link** (one-click reconcile across the whole inventory) or **manual
assignment** (pick policies for selected assets). This page covers both — and,
crucially, **why a given policy applies to a given asset**.

> Where: the **Discover** page (auto-link button), the **Assets** page (bulk
> *Assign policies*), and **Asset Detail** (*Link policy*). Verify the result on
> **Inventory Assignments**. Concept of fan-out:
> [../../esp/injection-and-scoped-injection.md](../../esp/injection-and-scoped-injection.md).

---

## The key idea: bind one, scan many

You bind a policy to an asset **once**. At scan time, **scoped injection** walks
from that asset and expands the policy to **every matching resource** — so
binding a storage-TLS policy to a *subscription* scans every storage account
under it, with a per-resource verdict each. You are not assigning a policy to
500 buckets by hand; you bind it to the account and the fan-out is automatic.
That's why "assignment" is lightweight and why **auto-link** can cover an entire
inventory in one click.

---

## A. Auto-link — reconcile the whole inventory

On the **Discover** page, the prominent **Auto-link policies** button does, in
the product's words: *"bind every policy to the assets it targets in one step —
matched by asset type and metadata. Scoped injection handles the per-resource
fan-out at scan time. Safe to re-run."*

**What it does:** the server reconciles registered policies against discovered
assets by **`target_asset_type`** — the asset-type hint each policy declares in
its META (see [../../esp/meta-and-control-mapping.md](../../esp/meta-and-control-mapping.md))
— and creates the links. It runs in two halves:

- **Auto-link** (`POST /api/inventory/asset-policies/auto-link`) — cloud/control-
  plane policies → matching cloud assets, by asset type + metadata.
- **Auto-link (internal)** (`…/auto-link-internal`) — host policies → matching
  hosts, by OS.

**The result** is a report: how many asset↔policy pairs were upserted and how
many policies found at least one matching asset. It's **idempotent** — re-run it
after every discovery sweep; newly-discovered resources get covered, nothing is
duplicated.

> Recommended path: **discover → auto-link → scan.** (`PostureScan` even warns
> *"No assets have policies linked. Run auto-link first."*)

---

## B. Manual assignment — pick policies for selected assets

When you want explicit control, assign manually:

- **Assets page → select assets → "Assign policies to N assets"** — opens a
  picker; submitting creates the cross-product (each selected asset × each
  selected policy).
- **Asset Detail → "Link policy"** — the same picker scoped to one asset.

The picker shows policies in a **directory tree** (mirroring the `.esp` layout)
or a flat list, with search by id/title/platform. The important control is the
**"Compatible only"** filter (on by default).

### Why a policy is shown as "compatible" — the reasoning

The picker sorts compatible policies first and greys out the rest with a **"not
compatible"** badge. Compatibility is decided by matching the policy's declared
target against the asset:

| Policy target | Matches | Rule |
|---|---|---|
| **Cloud / control-plane** policy | **cloud assets** | the policy's `platform` (`aws`/`azure`/`gcp`) equals the asset's **provider**. E.g. an `AWS::S3::Bucket` (provider `aws`) matches a policy with `platform aws`. |
| **Host** policy | **host assets** | the policy's `platform` matches the host's **OS family** — `linux` → linux/rocky/rhel/ubuntu; `windows` → windows; `rocky9` → Rocky; `rhel9` → RHEL; or an exact platform match. |

That heuristic *is* the "why": a policy applies to an asset because its target
type/platform lines up with what that asset is. The same logic underlies
auto-link (the server reconciles by `target_asset_type`); the picker just
surfaces it visually so you can see — and override — the match. Untick
"Compatible only" to assign a policy the heuristic wouldn't have suggested.

---

## C. Link status — the lifecycle of a binding

Every link carries a status, shown as a badge:

| Status | Meaning | When |
|---|---|---|
| **active** | scannable now | normal state; **host** links start here |
| **pending OBJECT add** (`pending_object_add`) | linked, but the policy's `SET` still needs the resource written in | **cloud / control-plane** links start here until the OBJECT is populated (auto-link/scoped injection resolves this) |
| **paused** | linked but skipped by scans/scheduler | temporarily out of scope |
| **archived** | retained for audit history, not scanned | retire a link without losing the record |

Transition with **Activate / Pause / Archive** (on Asset Detail's link actions
or in bulk). **Unlink** hard-deletes the link — the UI suggests **Archive
instead** to preserve history. Only **active** links are eligible to scan;
others are skipped with a counter.

> Model note: the canonical direction is purely **bind + inject** — a policy is
> bound to an asset, and `target_asset_type` + scoped injection do the rest. The
> cloud-vs-host distinction above and the `pending_object_add` status are just
> how the UI surfaces that same "what-applies-to-what" decision and whether a
> link's OBJECT has been populated yet.

---

## D. Verify scoping — Inventory Assignments

After auto-linking or bulk assignment, open **Inventory Assignments**: a flat
matrix of *every* asset↔policy link joined with both sides' identity, filterable
by status / platform / provider and searchable. Use it to answer **"where is
policy X applied?"** and **"is asset Y in scope for the right controls?"** before
you scan.

Next: [scanning-and-evidence.md](scanning-and-evidence.md).
