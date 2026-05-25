# az_entra_application_scoped

## Overview

**Injection-native variant of [`az_entra_application`](az_entra_application.md).**
Same checking logic — it reuses the
`az_entra_application` collection and validation logic **verbatim** through the generic
scoped wrapper (no edits to the base) — and the same collected-data
and state surface. The only difference is *how policies bind to it*:
`az_entra_application_scoped` is the target of dispatch-time **template
injection**.

You bind a policy to an **Entra ID app registration**
(`Microsoft.Graph/applications`), and at scan time the dispatcher resolves the
bound application asset and fills one OBJECT from its `display_name`. Bound
directly to an app, the walk is depth-0 (N=1). The engine then sees a normal
`SET` of one concrete OBJECT. The same `.esp` targets whichever app(s) it is
linked to — the policy text never changes.

**Platform:** Entra ID via Azure CLI (`az ad app list --display-name`).
**Channel:** `Local` (cloud-mode). **Scope:** Directory read
(`Application.Read.All`).

> **Note:** Entra directory objects are not yet produced by the discovery
> pipeline — there are no `Microsoft.Graph/applications` assets in inventory
> today. This contract + projection are in place so that the moment Entra app
> discovery lands, scoped policies bind and fan out with no further code change.

## Injection / Projection

`az_entra_application_scoped` registers a scoped projection
the dispatcher reads to fill each injected
OBJECT. asset_id is carried from the walk, so no provider-id reconstruction is
needed.

| Property | Value |
| --- | --- |
| `ctn_name` | `az_entra_application_scoped` |
| `target_asset_type` | `Microsoft.Graph/applications` |
| `display_name` | `<- display_name` (lookup key for `az ad app list --display-name`) |

The base collector accepts either `display_name` or `client_id`; the scoped
projection drives the `display_name` path (the asset's display name). No
resource group or subscription applies — app registrations live at directory
scope, not ARM scope.

**Placeholder form** (the dispatcher expands this to N concrete OBJECTs, then
strips the directive fields before the engine compiles):

```esp
SET apps union
    OBJECT t
        target `Microsoft.Graph/applications`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

Binding: a single app registration -> itself (depth-0, N=1); a container that
holds apps -> all apps under it.

## Object Fields

Injected at dispatch (not hand-authored): `display_name` — see the projection
above. Field schema is identical to
[`az_entra_application`](az_entra_application.md#object-fields).

## Commands Executed / Collected Data / State Fields

**Identical to [`az_entra_application`](az_entra_application.md)** — the
collection and validation logic are reused verbatim. Refer to that spec for the exact
`az ad app list` command, the full collected-data fields, and the state-field
table (`found`, `sign_in_audience`, ...).

## Collection Strategy

| Property | Value |
| --- | --- |
| Collector ID | `az_entra_application_scoped-scoped-collector` |
| Collector Type | `az_entra_application_scoped` |
| Underlying check | `az_entra_application` (reused via the scoped wrapper) |
| Collection Mode | API Call |
| Required Capabilities | `az_cli`, `directory_reader` |
| API Calls | 1 per resolved application |

## ESP Policy Example

```esp
META
    esp_id `az_entra_application_scoped-injection-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `azure`
    criticality `medium`
    control_mapping `INTERNAL:SCOPED-INJECTION`
    title `Entra ID app registration (scoped injection)`
    target_asset_type `Microsoft.Graph/applications`
META_END

DEF
    SET apps union
        OBJECT t
            target `Microsoft.Graph/applications`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE single_tenant
        found boolean = true
        sign_in_audience string = `AzureADMyOrg`
    STATE_END

    CRI AND
        CTN az_entra_application_scoped
            TEST all all AND
            STATE_REF single_tenant
            SET_REF apps
        CTN_END
    CRI_END
DEF_END
```

## Related CTN Types

| CTN Type | Relationship |
| --- | --- |
| [`az_entra_application`](az_entra_application.md) | The non-injection sibling whose collection and validation logic this reuses verbatim. |
| [`az_entra_group_scoped`](az_entra_group_scoped.md) | Sibling Entra directory-object scoped contract (same display-name projection shape). |
| [`az_entra_service_principal`](az_entra_service_principal.md) | Companion identity CTN (no scoped variant yet). |
