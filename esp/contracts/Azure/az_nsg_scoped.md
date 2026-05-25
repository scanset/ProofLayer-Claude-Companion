# az_nsg_scoped

## Overview

**Injection-native variant of [`az_nsg`](az_nsg.md).** Same checking logic
— it reuses the `az_nsg` check logic **verbatim** (no edits to the base) — and the same
collected-data and state surface. The only difference is *how policies bind to
it*: `az_nsg_scoped` is the target of dispatch-time **template injection**.

You bind a policy to a **resource group**, a **subscription**, or a **single
Network Security Group**, and at scan time the dispatcher walks the asset graph to the
`Microsoft.Network/networkSecurityGroups` descendants of the bound asset and fills one OBJECT per resource
from that resource's metadata. The engine then sees a normal `SET` of N
concrete OBJECTs. The same `.esp` therefore fans out or targets a single
resource purely based on where it is linked — the policy text never changes.

**Platform:** Azure (`az` CLI). **Channel:** `Local` (cloud-mode).
**Scope:** Control-plane only, read-only — `Reader` is sufficient.

## Injection / Projection

`az_nsg_scoped` declares a dispatch-time projection
the dispatcher reads to fill each injected OBJECT. asset_id is carried from the
walk, so no provider-id reconstruction is needed.

| Property | Value |
| --- | --- |
| `ctn_name` | `az_nsg_scoped` |
| `target_asset_type` | `Microsoft.Network/networkSecurityGroups` |
| `name` | `<- display_name` |
| `resource_group` | `<- metadata.resource_group` |
| `subscription` | `<- metadata.subscription_id` (feeds `az --subscription`) |

**Placeholder form** (the dispatcher expands this to N concrete OBJECTs, then
strips the directive fields before the engine compiles):

```esp
SET targets union
    OBJECT t
        target `Microsoft.Network/networkSecurityGroups`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

Binding: subscription -> all Network Security Groups under it; resource group -> that RG's
Network Security Groups; a single Network Security Group -> itself (depth-0, N=1).

## Object Fields

Injected at dispatch (not hand-authored): `name`, `resource_group`,
`subscription` — see the projection above. Field schema is identical to
[`az_nsg`](az_nsg.md#object-fields).

## Commands Executed / Collected Data / State Fields

**Identical to [`az_nsg`](az_nsg.md)** — the check logic is reused
verbatim. Refer to that spec for the exact `az` command, the full
collected-data fields, the RecordData structure, and the state-field table.

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type | `az_nsg_scoped` |
| Underlying check | Same as the base CTN (reused verbatim) |
| Collection Mode | Metadata |
| Required Capabilities | `az_cli`, `reader` |
| API Calls | 1 per resolved resource |

## ESP Policy Example

```esp
META
    esp_id `az_nsg_scoped-injection-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `azure`
    criticality `medium`
    control_mapping `INTERNAL:SCOPED-INJECTION`
    title `Network Security Group (scoped injection)`
    target_asset_type `Microsoft.Network/networkSecurityGroups`
META_END

DEF
    SET targets union
        OBJECT t
            target `Microsoft.Network/networkSecurityGroups`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE present
        found boolean = true
    STATE_END

    CRI AND
        CTN az_nsg_scoped
            TEST all all AND
            STATE_REF present
            SET_REF targets
        CTN_END
    CRI_END
DEF_END
```

`TEST all all` requires every resolved Network Security Group to satisfy the state — "X for
all" — while preserving a per-resource verdict + replay-hash leaf for each.

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_nsg`](az_nsg.md) | The non-injection sibling whose check logic this reuses verbatim. |
