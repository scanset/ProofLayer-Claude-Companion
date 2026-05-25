# az_activity_log_alert_scoped

## Overview

**Injection-native variant of [`az_activity_log_alert`](az_activity_log_alert.md).** Reuses the
`az_activity_log_alert` collection and validation logic **verbatim** via the generic scoped wrapper (no
edits to the base) — same collected-data and state surface. The difference is
binding: `az_activity_log_alert_scoped` is a dispatch-time **template-injection** target. Bind a
policy to a resource group / subscription / single Activity Log Alert and the dispatcher
walks to the `microsoft.insights/activityLogAlerts` descendants and fills one OBJECT per resource. The
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

target_asset_type: `microsoft.insights/activityLogAlerts`. Placeholder: `target` + `link` +
`behavior inject_from_bound_asset` inside a `SET ... union`.

## Object Fields

Injected at dispatch (not hand-authored): `name`, `resource_group`, `subscription`. Schema identical to
[`az_activity_log_alert`](az_activity_log_alert.md#object-fields).

## Commands / Collected Data / State Fields

**Identical to [`az_activity_log_alert`](az_activity_log_alert.md)** — collection and validation logic reused verbatim.
See that spec for the `az` command, collected-data fields, and state table.

## Collection Strategy

| Property | Value |
| --- | --- |
| Collector ID | `az_activity_log_alert_scoped-scoped-collector` |
| Collector Type | `az_activity_log_alert_scoped` |
| Underlying check | `az_activity_log_alert` (reused via the scoped wrapper) |
| API Calls | 1 per resolved resource |

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_activity_log_alert`](az_activity_log_alert.md) | The non-injection sibling whose collection and validation logic this reuses. |
