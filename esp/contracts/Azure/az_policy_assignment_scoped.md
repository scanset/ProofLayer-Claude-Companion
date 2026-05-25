# az_policy_assignment_scoped

## Overview

**Injection-native variant of [`az_policy_assignment`](az_policy_assignment.md).** Reuses the `az_policy_assignment` check logic **verbatim** (no
edits to the base) — same collected-data and state surface. The difference is
binding: `az_policy_assignment_scoped` is a dispatch-time **template-injection** target. Bind a
policy to a resource group / subscription / single Policy Assignment and the dispatcher
walks to the `Microsoft.Authorization/policyAssignments` descendants and fills one OBJECT per resource. The
same `.esp` fans out or targets one resource based purely on where it is
linked.

**Platform:** Azure (`az` CLI). **Channel:** `Local`. **Scope:** read-only (`Reader`).

## Injection / Projection

A dispatch-time projection, read by the
 dispatcher; asset_id carried from the walk (no provider-id builder).

| Field | Source |
| --- | --- |
| `name` | `<- metadata.name` (short policy name) |
| `scope` | `<- metadata.scope` |
| `subscription` | `<- metadata.subscription_id` (optional) |

target_asset_type: `Microsoft.Authorization/policyAssignments`. Placeholder: `target` + `link` +
`behavior inject_from_bound_asset` inside a `SET ... union`.

## Object Fields

Injected at dispatch (not hand-authored): `name`, `scope`, `subscription`. Schema identical to
[`az_policy_assignment`](az_policy_assignment.md#object-fields).

## Commands / Collected Data / State Fields

**Identical to [`az_policy_assignment`](az_policy_assignment.md)** — check logic reused verbatim.
See that spec for the `az` command, collected-data fields, and state table.

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type | `az_policy_assignment_scoped` |
| Underlying check | Same as the base CTN (reused verbatim) |
| API Calls | 1 per resolved resource |

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_policy_assignment`](az_policy_assignment.md) | The non-injection sibling whose check logic this reuses. |
