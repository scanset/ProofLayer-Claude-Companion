# az_defender_pricing_scoped

## Overview

**Injection-native variant of [`az_defender_pricing`](az_defender_pricing.md).** Reuses the
`az_defender_pricing` collection and validation logic **verbatim** via the generic scoped wrapper (no
edits to the base) — same collected-data and state surface. The difference is
binding: `az_defender_pricing_scoped` is a dispatch-time **template-injection** target. Bind a
policy to a resource group / subscription / single Defender Pricing and the dispatcher
walks to the `Microsoft.Security/pricings` descendants and fills one OBJECT per resource. The
same `.esp` fans out or targets one resource based purely on where it is
linked.

**Platform:** Azure (`az` CLI). **Channel:** `Local`. **Scope:** read-only (`Reader`).

## Injection / Projection

A scoped projection, read by the
dispatcher; asset_id carried from the walk (no provider-id builder).

| Field | Source |
| --- | --- |
| `name` | `<- display_name` |
| `subscription` | `<- metadata.subscription_id` |

target_asset_type: `Microsoft.Security/pricings`. Placeholder: `target` + `link` +
`behavior inject_from_bound_asset` inside a `SET ... union`.

## Object Fields

Injected at dispatch (not hand-authored): `name`, `subscription`. Schema identical to
[`az_defender_pricing`](az_defender_pricing.md#object-fields).

## Commands / Collected Data / State Fields

**Identical to [`az_defender_pricing`](az_defender_pricing.md)** — collection and validation logic reused verbatim.
See that spec for the `az` command, collected-data fields, and state table.

## Collection Strategy

| Property | Value |
| --- | --- |
| Collector ID | `az_defender_pricing_scoped-scoped-collector` |
| Collector Type | `az_defender_pricing_scoped` |
| Underlying check | `az_defender_pricing` (reused via the scoped wrapper) |
| API Calls | 1 per resolved resource |

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_defender_pricing`](az_defender_pricing.md) | The non-injection sibling whose collection and validation logic this reuses. |
