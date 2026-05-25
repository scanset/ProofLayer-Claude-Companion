# az_entra_group_scoped

## Overview

**Injection-native variant of [`az_entra_group`](az_entra_group.md).** Same
checking logic — it reuses the `az_entra_group`
collection and validation logic **verbatim** through the generic scoped wrapper (no edits to
the base) — and the same collected-data and state surface. The only difference
is *how policies bind to it*: `az_entra_group_scoped` is the target of
dispatch-time **template injection**.

You bind a policy to an **Entra ID group** (`Microsoft.Graph/groups`), and at
scan time the dispatcher resolves the bound group asset and fills one OBJECT
from its `display_name`. Bound directly to a group, the walk is depth-0 (N=1).
The engine then sees a normal `SET` of one concrete OBJECT. The same `.esp`
targets whichever group(s) it is linked to — the policy text never changes.

**Platform:** Entra ID via Azure CLI (`az ad group show`). **Channel:** `Local`
(cloud-mode). **Scope:** Directory read (`Directory.Read.All` / `Group.Read.All`).

> **Note:** Entra directory objects are not yet produced by the discovery
> pipeline — there are no `Microsoft.Graph/groups` assets in inventory today.
> This contract + projection are in place so that the moment Entra group
> discovery lands, scoped policies bind and fan out with no further code change.

## Injection / Projection

`az_entra_group_scoped` registers a scoped projection
the dispatcher reads to fill each injected
OBJECT. asset_id is carried from the walk, so no provider-id reconstruction is
needed.

| Property | Value |
| --- | --- |
| `ctn_name` | `az_entra_group_scoped` |
| `target_asset_type` | `Microsoft.Graph/groups` |
| `display_name` | `<- display_name` (the lookup key for `az ad group show --group`) |

No resource group or subscription applies — Entra groups live at directory
scope, not ARM scope.

**Placeholder form** (the dispatcher expands this to N concrete OBJECTs, then
strips the directive fields before the engine compiles):

```esp
SET groups union
    OBJECT t
        target `Microsoft.Graph/groups`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

Binding: a single group -> itself (depth-0, N=1); a container that holds groups
-> all groups under it.

## Object Fields

Injected at dispatch (not hand-authored): `display_name` — see the projection
above. Field schema is identical to
[`az_entra_group`](az_entra_group.md#object-fields).

## Commands Executed / Collected Data / State Fields

**Identical to [`az_entra_group`](az_entra_group.md)** — the collection and validation logic
are reused verbatim. Refer to that spec for the exact `az ad group show`
command, the full collected-data fields, and the state-field table
(`found`, `security_enabled`, `mail_enabled`, `description`, ...).

## Collection Strategy

| Property | Value |
| --- | --- |
| Collector ID | `az_entra_group_scoped-scoped-collector` |
| Collector Type | `az_entra_group_scoped` |
| Underlying check | `az_entra_group` (reused via the scoped wrapper) |
| Collection Mode | API Call |
| Required Capabilities | `az_cli`, `directory_reader` |
| API Calls | 1 per resolved group |

## ESP Policy Example

```esp
META
    esp_id `az_entra_group_scoped-injection-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `azure`
    criticality `medium`
    control_mapping `INTERNAL:SCOPED-INJECTION`
    title `Entra ID group (scoped injection)`
    target_asset_type `Microsoft.Graph/groups`
META_END

DEF
    SET groups union
        OBJECT t
            target `Microsoft.Graph/groups`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE present
        found boolean = true
        security_enabled boolean = true
    STATE_END

    CRI AND
        CTN az_entra_group_scoped
            TEST all all AND
            STATE_REF present
            SET_REF groups
        CTN_END
    CRI_END
DEF_END
```

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_entra_group`](az_entra_group.md) | The non-injection sibling whose collection and validation logic this reuses verbatim. |
| [`az_entra_application_scoped`](az_entra_application_scoped.md) | Sibling Entra directory-object scoped contract (same display-name projection shape). |
