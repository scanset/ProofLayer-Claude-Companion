# az_managed_disk_scoped

## Overview

**Injection-native variant of [`az_managed_disk`](az_managed_disk.md).** Same checking logic
— it reuses the `az_managed_disk` check logic **verbatim** (no edits to the base) — and the same
collected-data and state surface. The only difference is *how policies bind to
it*: `az_managed_disk_scoped` is the target of dispatch-time **template injection**.

You bind a policy to a **resource group**, a **subscription**, or a **single
Managed Disk**, and at scan time the dispatcher walks the asset graph to the
`Microsoft.Compute/disks` descendants of the bound asset and fills one OBJECT per resource
from that resource's metadata. The engine then sees a normal `SET` of N
concrete OBJECTs. The same `.esp` therefore fans out or targets a single
resource purely based on where it is linked — the policy text never changes.

**Platform:** Azure (`az` CLI). **Channel:** `Local` (cloud-mode).
**Scope:** Control-plane only, read-only — `Reader` is sufficient.

## Injection / Projection

`az_managed_disk_scoped` declares a dispatch-time projection
the dispatcher reads to fill each injected OBJECT. asset_id is carried from the
walk, so no provider-id reconstruction is needed.

| Property | Value |
| --- | --- |
| `ctn_name` | `az_managed_disk_scoped` |
| `target_asset_type` | `Microsoft.Compute/disks` |
| `name` | `<- display_name` |
| `resource_group` | `<- metadata.resource_group` |
| `subscription` | `<- metadata.subscription_id` (feeds `az --subscription`) |

**Placeholder form** (the dispatcher expands this to N concrete OBJECTs, then
strips the directive fields before the engine compiles):

```esp
SET targets union
    OBJECT t
        target `Microsoft.Compute/disks`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

Binding: subscription -> all Managed Disks under it; resource group -> that RG's
Managed Disks; a single Managed Disk -> itself (depth-0, N=1).

## Object Fields

Injected at dispatch (not hand-authored): `name`, `resource_group`,
`subscription` — see the projection above. Field schema is identical to
[`az_managed_disk`](az_managed_disk.md#object-fields).

## Commands Executed / Collected Data / State Fields

**Identical to [`az_managed_disk`](az_managed_disk.md)** — the check logic is reused
verbatim. Refer to that spec for the exact `az` command, the full
collected-data fields, the RecordData structure, and the state-field table.

## Collection Strategy

| Property | Value |
| --- | --- |
| CTN Type | `az_managed_disk_scoped` |
| Underlying check | Same as the base CTN (reused verbatim) |
| Collection Mode | Metadata |
| Required Capabilities | `az_cli`, `reader` |
| API Calls | 1 per resolved resource |

## ESP Policy Example

```esp
META
    esp_id `az_managed_disk_scoped-injection-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `azure`
    criticality `medium`
    control_mapping `INTERNAL:SCOPED-INJECTION`
    title `Managed Disk (scoped injection)`
    target_asset_type `Microsoft.Compute/disks`
META_END

DEF
    SET targets union
        OBJECT t
            target `Microsoft.Compute/disks`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE present
        found boolean = true
    STATE_END

    CRI AND
        CTN az_managed_disk_scoped
            TEST all all AND
            STATE_REF present
            SET_REF targets
        CTN_END
    CRI_END
DEF_END
```

`TEST all all` requires every resolved Managed Disk to satisfy the state — "X for
all" — while preserving a per-resource verdict + replay-hash leaf for each.

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_managed_disk`](az_managed_disk.md) | The non-injection sibling whose check logic this reuses verbatim. |
