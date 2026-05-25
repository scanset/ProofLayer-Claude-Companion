# az_vnet_scoped

## Overview

**Injection-native variant of [`az_virtual_network`](az_virtual_network.md).**
Identical checking logic — it reuses the exact same collection and validation
(`az network vnet show ... --output json`) and the exact same collected-data
and state surface — but it is exposed under the distinct CTN name
`az_vnet_scoped` so it can carry an **injection-native projection**.

The difference is *how policies bind to it*. Where `az_virtual_network`
expects each VNet's OBJECT to be authored (or synced) into the policy file,
`az_vnet_scoped` is meant to be used with an `inject_from_bound_asset`
placeholder: you bind a policy to a **resource group** (or subscription, or a
single vnet), and at scan-dispatch time the dispatcher walks the asset graph
to the `Microsoft.Network/virtualNetworks` descendants and fills one OBJECT per
vnet from that vnet's metadata. The engine then sees a normal `SET` of N
concrete vnet OBJECTs.

The CTN never modifies any resource, never calls data-plane APIs, and never
requires any Azure permission above `Reader`.

**Platform:** Azure (requires `az` CLI binary on PATH, authenticated via any
supported mode)
**Collection Method:** Single Azure CLI command per object, run in a hardened,
sandboxed subprocess (same as `az_virtual_network`).
**Scope:** Control-plane only, read-only.
**Channel:** `Local` (cloud-mode — shells out locally, reaches the control
plane through the credential's env).

---

## Environment Variables

Identical to every Azure CTN. The hardened execution environment is cleared
before the `az` CLI is spawned, then re-injects the Azure auth surface:

| Purpose                       | Env Var(s)                                                          |
| ----------------------------- | ------------------------------------------------------------------- |
| SPN + client secret           | `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`         |
| Subscription pin              | `AZURE_SUBSCRIPTION_ID`                                             |
| SPN + client certificate      | `AZURE_CLIENT_CERTIFICATE_PATH`, `AZURE_CLIENT_CERTIFICATE_PASSWORD`|
| Cached `az login`             | `HOME`, `AZURE_CONFIG_DIR`                                          |

### Supported auth modes

| Mode                         | Required env                                                          |
| ---------------------------- | --------------------------------------------------------------------- |
| SPN with client secret       | `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`           |
| SPN with client certificate  | `AZURE_CLIENT_ID`, `AZURE_CLIENT_CERTIFICATE_PATH`, `AZURE_TENANT_ID` |
| Cached `az login`            | `HOME` (or `AZURE_CONFIG_DIR`)                                        |

Subscription selection precedence: the OBJECT's injected `subscription` field >
`AZURE_SUBSCRIPTION_ID` env > cached-config default.

---

## Object Fields

These are **not hand-authored** in the policy. They are injected at dispatch
time from each resolved vnet's the asset inventory metadata (see Injection).

| Field            | Type   | Required | Injected from                          | Example                                 |
| ---------------- | ------ | -------- | -------------------------------------- | --------------------------------------- |
| `name`           | string | **Yes**  | asset `display_name`                   | `pltestlz-tenant-b-vnet`                |
| `resource_group` | string | **Yes**  | `metadata.resource_group`              | `pltestlz-tenant-b-rg`                  |
| `subscription`   | string | opt      | `metadata.subscription_id`             | `2f3a8603-9425-446b-8fa4-09bb61becdcc`  |

---

## Injection / Projection

`az_vnet_scoped` declares a typed dispatch-time projection that the
dispatcher consumes:

| Property            | Value                                                              |
| ------------------- | ----------------------------------------------------------------- |
| `ctn_name`          | `az_vnet_scoped`                                                  |
| `target_asset_type` | `Microsoft.Network/virtualNetworks`                              |
| `name`              | `<- display_name`                                                |
| `resource_group`    | `<- metadata.resource_group`                                     |
| `subscription`      | `<- metadata.subscription_id` (also feeds the provider_id builder) |
| `provider_id`       | `/subscriptions/{subscription}/resourceGroups/{resource_group}/providers/Microsoft.Network/virtualNetworks/{name}` |

**Placeholder form** in the `.esp` (the dispatcher expands this to N concrete
OBJECTs, one per resolved vnet, then removes the directive fields before the
engine compiles the file):

```esp
SET vnets union
    OBJECT v
        target `Microsoft.Network/virtualNetworks`   # asset type to resolve to
        link `contains`                              # relation to walk from the bound asset
        behavior inject_from_bound_asset             # dispatch-time descendant expansion
    OBJECT_END
SET_END
```

Binding semantics:

- Bind to a **resource group** → walk `contains` → all vnets in the RG (N OBJECTs).
- Bind to the **subscription** → all vnets under it.
- Bind to a **single vnet** → that vnet only (depth-0, N=1).

`provider_id` lets `ctn_results.asset_id` back-map each per-vnet verdict to its
asset row, so per-vnet posture and replay-hash leaves are preserved.

---

## Commands Executed

```
az network vnet show --name <name> \
    --resource-group <resource_group> \
    [--subscription <subscription>] \
    --output json
```

One call per resolved vnet OBJECT. Identical to `az_virtual_network`.

---

## Collected Data Fields

Identical to `az_virtual_network`. Key scalars/booleans/integers:

| Field                       | Type    | Source                                              |
| --------------------------- | ------- | --------------------------------------------------- |
| `found`                     | boolean | true on successful show, false on NotFound          |
| `name` / `id` / `location`  | string  | `name` / `id` / `location`                          |
| `resource_group`            | string  | `resourceGroup`                                     |
| `provisioning_state`        | string  | `provisioningState`                                 |
| `address_prefix`            | string  | first `addressSpace.addressPrefixes[]`              |
| `has_subnets`               | boolean | `subnets.len() > 0`                                 |
| `all_subnets_have_nsg`      | boolean | every subnet has a non-null `networkSecurityGroup`  |
| `ddos_protection_enabled`   | boolean | `enableDdosProtection`                              |
| `has_peerings`              | boolean | `virtualNetworkPeerings.len() > 0`                  |
| `has_flow_logs`             | boolean | `flowLogs.len() > 0`                                |
| `subnet_count`              | integer | `subnets.len()`                                     |
| `subnets_without_nsg_count` | integer | subnets where `networkSecurityGroup` is null        |
| `peering_count`             | integer | `virtualNetworkPeerings.len()`                      |
| `flow_log_count`            | integer | `flowLogs.len()`                                    |
| `resource`                  | RecordData | full `az network vnet show` object for record_checks |

See [`az_virtual_network`](az_virtual_network.md) for the complete field table,
RecordData structure, and derived-field semantics — they are shared verbatim.

---

## State Fields

Identical to `az_virtual_network` (same validation logic). Common ones:

| State Field                 | Type       | Operations                          |
| --------------------------- | ---------- | ----------------------------------- |
| `found`                     | boolean    | `=`, `!=`                           |
| `provisioning_state`        | string     | `=`, `!=`                           |
| `has_subnets`               | boolean    | `=`, `!=`                           |
| `all_subnets_have_nsg`      | boolean    | `=`, `!=`                           |
| `ddos_protection_enabled`   | boolean    | `=`, `!=`                           |
| `has_peerings`              | boolean    | `=`, `!=`                           |
| `has_flow_logs`             | boolean    | `=`, `!=`                           |
| `subnet_count`              | integer    | `=`, `!=`, `>`, `>=`, `<`, `<=`     |
| `subnets_without_nsg_count` | integer    | `=`, `!=`, `>`, `>=`, `<`, `<=`     |
| `peering_count`             | integer    | `=`, `!=`, `>`, `>=`, `<`, `<=`     |
| `record`                    | RecordData | (record checks against `resource`)  |

---

## Collection Strategy

| Property                 | Value                                              |
| ------------------------ | -------------------------------------------------- |
| CTN Type                 | `az_vnet_scoped`                                   |
| Underlying check         | Same as `az_virtual_network` (reused verbatim)     |
| Collection Mode          | Metadata                                           |
| Required Capabilities    | `az_cli`, `reader`                                 |
| Per-call Timeout         | 30s                                                |
| API Calls                | 1 per resolved vnet                                |

---

## Required Azure Permissions

`Reader` at subscription, RG, or VNet scope. Pure ARM GET; no data plane.

---

## ESP Policy Examples

### Injection-native baseline — bind to an RG, scan every vnet

```esp
META
    esp_id `az-vnet-scoped-injection-001`
    version `1.0.0`
    dsl_schema_version `1.0.0`
    platform `azure`
    criticality `medium`
    control_mapping `KSI:KSI-CNA-RNT`
    title `Azure VNet baseline (injection-native)`
    target_asset_type `Microsoft.Network/virtualNetworks`
META_END

DEF
    SET vnets union
        OBJECT v
            target `Microsoft.Network/virtualNetworks`
            link `contains`
            behavior inject_from_bound_asset
        OBJECT_END
    SET_END

    STATE vnet_baseline
        found boolean = true
        provisioning_state string = `Succeeded`
        has_subnets boolean = true
    STATE_END

    CRI AND
        CTN az_vnet_scoped
            TEST all all AND
            STATE_REF vnet_baseline
            SET_REF vnets
        CTN_END
    CRI_END
DEF_END
```

`TEST all all` requires *every* resolved vnet to satisfy the state — "X for all
children" — while preserving a per-vnet verdict + replay-hash leaf for each.

---

## Error Conditions

Identical to `az_virtual_network`:

| Condition                                   | Behavior                                      |
| ------------------------------------------- | --------------------------------------------- |
| VNet does not exist                         | `found=false`, `resource={}` (ResourceNotFound) |
| RG missing / no access                      | `found=false` (AuthorizationFailed scoped to vnet) |
| `name` / `resource_group` missing from OBJECT | Invalid object configuration — Error         |
| `az` missing / not authenticated            | Collection fails — error bubbles up           |

Injection-side: if the bound asset has no `Microsoft.Network/virtualNetworks`
descendants via the requested `link`, the dispatcher fails the scan with a
clear *"no `<target>` reachable … nothing to scan"* (rather than emitting an
empty `SET`).

---

## Non-Goals

Same as `az_virtual_network` (no mutation, no data-plane probing, no
effective-route evaluation). One VNet inspected per OBJECT — cross-vnet
correlation is out of scope; "all vnets under X" is achieved by the **scope
walk** (the binding), not by the CTN.

---

## Related CTN Types

| CTN Type             | Relationship                                                     |
| -------------------- | ---------------------------------------------------------------- |
| `az_virtual_network` | The non-injection sibling whose check logic this reuses verbatim. |
| `az_resource_group`  | Common bind target — the RG you attach the policy to.            |
| `az_nsg`             | NSGs attached to subnets within the resolved vnets.              |
