# az_role_assignment_list_scoped

## Overview

**Injection-native variant of [`az_role_assignment_list`](az_role_assignment_list.md).**
Same checking logic — it reuses the `az_role_assignment_list` check logic
**verbatim** (no edits to the base) — and the same collected-data
and state surface. The only difference is *how policies bind to it*:
`az_role_assignment_list_scoped` is the target of dispatch-time **template
injection**.

You bind a policy to an **Azure subscription**, and at scan time the dispatcher
resolves the bound subscription asset and fills one OBJECT from its metadata.
Because the binding *is* the subscription, the walk is depth-0 (N=1) — the
subscription resolves to itself. The engine then sees a normal `SET` of one
concrete OBJECT enumerating that subscription's role assignments. The same
`.esp` therefore targets whichever subscription it is linked to — the policy
text never changes.

**Platform:** Azure (`az` CLI). **Channel:** `Local` (cloud-mode).
**Scope:** Control-plane only, read-only — `Reader` is sufficient.

## Injection / Projection

`az_role_assignment_list_scoped` declares a dispatch-time projection the
dispatcher reads to fill each injected OBJECT. asset_id is carried from the
walk, so no provider-id reconstruction is needed.

| Property | Value |
| --- | --- |
| `ctn_name` | `az_role_assignment_list_scoped` |
| `target_asset_type` | `Microsoft.Resources/subscriptions` |
| `scope` | `<- literal `subscription`` (the required label) |
| `subscription` | `<- metadata.subscription_id` (builds the ARM `roleAssignments` URL) |

The base check requires a `scope` label (used to build the collection
target) and uses `subscription` to build the ARM
`Microsoft.Authorization/roleAssignments` URL queried via `az rest` — a pure
management-plane GET with **no Microsoft Graph call** (see the base spec for
the rationale). The `name` field the hand-authored OBJECT carried is not read
and is therefore not projected; the dispatcher derives a
stable OBJECT identifier (`inj_0_<display_name>`) automatically.

**Placeholder form** (the dispatcher expands this to one concrete OBJECT, then
strips the directive fields before the engine compiles):

```esp
SET subscriptions union
    OBJECT t
        target `Microsoft.Resources/subscriptions`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

Binding: a single subscription -> itself (depth-0, N=1).

## Object Fields

Injected at dispatch (not hand-authored): `scope`, `subscription` — see the
projection above. Field schema is identical to
[`az_role_assignment_list`](az_role_assignment_list.md#object-fields).

## Commands Executed / Collected Data / State Fields

**Identical to [`az_role_assignment_list`](az_role_assignment_list.md)** — the
check logic is reused verbatim. Refer to that spec for the exact
`az rest` ARM command (Graph-free), the full collected-data fields, the
per-assignment RecordData structure, and the state-field table
(`found`, `role_count`, `roles.*`).

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type | `az_role_assignment_list_scoped` |
| Underlying check | Same as the base CTN (reused verbatim) |
| Collection Mode | API Call |
| Required Capabilities | `az_cli`, `reader` |
| API Calls | 1 per resolved subscription |

## ESP Policy Example

```esp
META
    esp_id `az_role_assignment_list_scoped-injection-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `azure`
    criticality `medium`
    control_mapping `INTERNAL:SCOPED-INJECTION`
    title `Role assignments at subscription scope (scoped injection)`
    target_asset_type `Microsoft.Resources/subscriptions`
META_END

DEF
    SET subscriptions union
        OBJECT t
            target `Microsoft.Resources/subscriptions`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE rbac_has_assignments
        found boolean = true
        role_count int >= 1
    STATE_END

    CRI AND
        CTN az_role_assignment_list_scoped
            TEST all all AND
            STATE_REF rbac_has_assignments
            SET_REF subscriptions
        CTN_END
    CRI_END
DEF_END
```

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_role_assignment_list`](az_role_assignment_list.md) | The non-injection sibling whose check logic this reuses verbatim. |
| [`az_role_assignment`](az_role_assignment.md) | Per-assignment check (no scoped variant — `role_name` is not graph-projectable). |
