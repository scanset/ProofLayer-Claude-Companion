# az_load_balancer_scoped

## Overview

**Injection-native variant of [`az_load_balancer`](az_load_balancer.md).** Reuses the
`az_load_balancer` collection and validation logic **verbatim** via the generic scoped wrapper (no
edits to the base) — same collected-data and state surface. The difference is
binding: `az_load_balancer_scoped` is a dispatch-time **template-injection** target. Bind a
policy to a resource group / subscription / single Load Balancer and the dispatcher
walks to the `Microsoft.Network/loadBalancers` descendants and fills one OBJECT per resource. The
same `.esp` fans out or targets one resource based purely on where it is
linked.

**Platform:** Azure (`az` CLI). **Channel:** `Local`. **Scope:** read-only (`Reader`).

## Injection / Projection

A scoped projection, read by the
dispatcher; asset_id carried from the walk (no provider-id builder).

| Field | Source |
| --- | --- |
| `name` | `<- display_name` |
| `resource_group` | `<- metadata.resource_group` |
| `subscription` | `<- metadata.subscription_id` |

target_asset_type: `Microsoft.Network/loadBalancers`. Placeholder: `target` + `link` +
`behavior inject_from_bound_asset` inside a `SET ... union`.

## Object Fields

Injected at dispatch (not hand-authored): `name`, `resource_group`, `subscription`. Schema identical to
[`az_load_balancer`](az_load_balancer.md#object-fields).

## Commands / Collected Data / State Fields

**Identical to [`az_load_balancer`](az_load_balancer.md)** — collection and validation logic reused verbatim.
See that spec for the `az` command, collected-data fields, and state table.

## Collection Strategy

| Property | Value |
| --- | --- |
| Collector ID | `az_load_balancer_scoped-scoped-collector` |
| Collector Type | `az_load_balancer_scoped` |
| Underlying check | `az_load_balancer` (reused via the scoped wrapper) |
| API Calls | 1 per resolved resource |

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_load_balancer`](az_load_balancer.md) | The non-injection sibling whose collection and validation logic this reuses. |
