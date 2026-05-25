# az_role_assignment_list

## Overview

List-mode CTN that enumerates Azure RBAC role assignments via the **ARM
REST API** (`az rest`), returning one record per assignment at or below
the subscription scope. Each record carries the principal id (who), the
role definition (what permissions), and the scope (where).

**Why `az rest`, not `az role assignment list`:** the CLI list helper makes
a *second* call to Microsoft Graph (`/directoryObjects/getByIds`) to enrich
each row with `principalName`/`displayName`. That Graph round-trip is a
fragile external dependency — a transient TLS reset there aborts the entire
command (exit 1) and sinks the scan — and these checks never need principal
*names*. Querying the management-plane `roleAssignments` endpoint directly
returns the same ARM rows with **no Graph call**. The trade-off: ARM does not
return `roleDefinitionName`, so the collector resolves it from the stable
built-in role-definition GUID for the common roles (Owner, Contributor,
Reader, User Access Administrator); other roles keep `role_definition_id`.

**Platform:** Azure (requires `az` CLI binary on PATH, authenticated via
any supported mode)
**Collection Method:** Single `az rest` GET against the management plane,
run in a hardened, sandboxed subprocess. Control-plane only — never Graph.

**Note:** The record `name` field is the role assignment's GUID, not a
friendly display name. `principal_name` is **not** collected (it would require
the Graph call we deliberately avoid) — use `principal_id` for the identity and
`role_definition_name` (built-ins only) / `role_definition_id` for the role.

---

## Environment Variables

The execution environment is cleared before `az` is spawned, then only
the variables below are re-injected. Any variable not set on the host is
silently skipped.

**You do not need to set all of these.** Pick ONE auth mode and configure
only its required vars -- the rest stay unset and are simply skipped.

### Auth mode: SPN with client secret

| Env var                              | Required | Purpose                     |
| ------------------------------------ | :------: | --------------------------- |
| `AZURE_CLIENT_ID`                    |    Yes   | SPN application (client) ID |
| `AZURE_CLIENT_SECRET`                |    Yes   | SPN client secret           |
| `AZURE_TENANT_ID`                    |    Yes   | Entra tenant GUID           |
| `AZURE_SUBSCRIPTION_ID`              |    opt   | Default subscription pin    |

### Auth mode: SPN with client certificate

| Env var                              | Required | Purpose                                |
| ------------------------------------ | :------: | -------------------------------------- |
| `AZURE_CLIENT_ID`                    |    Yes   | SPN application (client) ID            |
| `AZURE_TENANT_ID`                    |    Yes   | Entra tenant GUID                      |
| `AZURE_CLIENT_CERTIFICATE_PATH`      |    Yes   | Path to PEM/PFX cert on disk           |
| `AZURE_CLIENT_CERTIFICATE_PASSWORD`  |    opt   | Cert password if PFX is encrypted      |
| `AZURE_SUBSCRIPTION_ID`              |    opt   | Default subscription pin               |

### Auth mode: Workload Identity (federated OIDC)

| Env var                              | Required | Purpose                                  |
| ------------------------------------ | :------: | ---------------------------------------- |
| `AZURE_CLIENT_ID`                    |    Yes   | Federated identity application ID        |
| `AZURE_TENANT_ID`                    |    Yes   | Entra tenant GUID                        |
| `AZURE_FEDERATED_TOKEN_FILE`         |    Yes   | Path to OIDC token file                  |
| `AZURE_AUTHORITY_HOST`               |    opt   | Sovereign cloud override                 |
| `AZURE_SUBSCRIPTION_ID`              |    opt   | Default subscription pin                 |

### Auth mode: Managed Identity

No explicit env vars on the agent. Azure injects `IDENTITY_ENDPOINT` and
`IDENTITY_HEADER` (or legacy `MSI_ENDPOINT` / `MSI_SECRET`) on a VM or
App Service with an assigned identity; the passthrough list forwards
them to `az`.

### Auth mode: Cached `az login`

| Env var                              | Required | Purpose                                            |
| ------------------------------------ | :------: | -------------------------------------------------- |
| `HOME`                               |    Yes   | `az` looks for `~/.azure/` token cache under HOME  |
| `AZURE_CONFIG_DIR`                   |    opt   | Overrides `~/.azure/` location                     |
| `AZURE_SUBSCRIPTION_ID`              |    opt   | Overrides the cached default subscription          |

### Locale (all modes)

| Env var              | Required | Purpose                                     |
| -------------------- | :------: | ------------------------------------------- |
| `LANG` / `LC_ALL`    |    opt   | Suppresses Python locale warnings from `az` |

---

## Object Fields

| Field          | Type   | Required | Description                                                                              | Example                                |
| -------------- | ------ | -------- | ---------------------------------------------------------------------------------------- | -------------------------------------- |
| `scope`        | string | **Yes**  | Discovery-scope label. `subscription` enumerates every assignment at or below subscription scope. | `subscription`                         |
| `subscription` | string | opt      | Subscription ID for the ARM URL. If absent, the collector resolves the active subscription via `az account show`. | `00000000-0000-0000-0000-000000000000` |

---

## Commands Executed

```
az rest \
    --method get \
    --url "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
    --output json
```

A single management-plane GET. The response wraps the rows in a `value`
array (one page; hundreds of assignments would paginate via `nextLink`,
far beyond any realistic subscription-scope RBAC footprint). No Graph call
is made, so `principalName`/`roleDefinitionName` are absent from the raw
response — the collector derives `role_definition_name` from the role GUID.

**Sample response (abbreviated):**

```json
{
  "value": [
    {
      "id": "/subscriptions/.../providers/Microsoft.Authorization/roleAssignments/aaaaaaaa-aaaa-...",
      "name": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      "type": "Microsoft.Authorization/roleAssignments",
      "properties": {
        "scope": "/subscriptions/00000000-...",
        "principalId": "11111111-1111-1111-1111-111111111111",
        "principalType": "Group",
        "roleDefinitionId": "/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-...",
        "createdOn": "2026-01-12T14:22:01.0000000Z",
        "updatedOn": "2026-01-12T14:22:01.0000000Z"
      }
    }
  ]
}
```

The collector flattens `properties.*` into the projected record and adds
`role_definition_name` for well-known built-in roles (here, `acdd72a7-…` →
`Reader`).

---

## Collected Data Fields

### Scalar Fields

| Field        | Type    | Always Present | Source                                                              |
| ------------ | ------- | -------------- | ------------------------------------------------------------------- |
| `found`      | boolean | Yes            | Derived -- `true` when one or more assignments are returned (`role_count > 0`). |
| `role_count` | integer | Yes            | Length of the returned `value` array (`0` if no assignments are visible).   |

### List/Records Field

| Field   | Type       | Always Present | Description                                                             |
| ------- | ---------- | -------------- | ----------------------------------------------------------------------- |
| `roles` | RecordData | Yes            | Projected record array. Empty `[]` when none visible (still `found=true`). |

---

## Record/List Structure

| Path                          | Type   | Example Value                                                              |
| ----------------------------- | ------ | -------------------------------------------------------------------------- |
| `roles.*.id`                  | string | `"/subscriptions/.../roleAssignments/aaaaaaaa-aaaa-..."`                   |
| `roles.*.name`                | string | `"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"` (assignment GUID, NOT friendly)   |
| `roles.*.type`                | string | `"Microsoft.Authorization/roleAssignments"`                                |
| `roles.*.scope`               | string | `"/subscriptions/00000000-..."` (the scope at which the role was granted) |
| `roles.*.principal_id`        | string | `"11111111-1111-1111-1111-111111111111"`                                   |
| `roles.*.principal_type`      | string | `"User"`, `"Group"`, `"ServicePrincipal"`, `"ManagedIdentity"`             |
| `roles.*.role_definition_id`  | string | `"/subscriptions/.../roleDefinitions/acdd72a7-3385-..."` (always present)  |
| `roles.*.role_definition_name`| string | `"Owner"`, `"Contributor"`, `"Reader"`, `"User Access Administrator"` — **built-ins only** (GUID-derived); absent for custom/other roles |
| `roles.*.created_on`          | string | `"2026-01-12T14:22:01.000000+00:00"`                                       |
| `roles.*.updated_on`          | string | `"2026-01-12T14:22:01.000000+00:00"`                                       |

---

## State Fields

| State Field  | Type       | Allowed Operations              | Maps To Collected Field |
| ------------ | ---------- | ------------------------------- | ----------------------- |
| `found`      | boolean    | `=`, `!=`                       | `found`                 |
| `role_count` | integer    | `=`, `!=`, `>`, `>=`, `<`, `<=` | `role_count`            |
| `roles`      | RecordData | (record checks)                 | `roles`                 |

---

## Collection Strategy

| Property                     | Value                             |
| ---------------------------- | --------------------------------- |
| CTN Type               | `az_role_assignment_list`         |
| Collection Mode              | Metadata                          |
| Required Capabilities        | `az_cli`, `reader`                |
| Expected Collection Time     | ~3000ms                           |
| Memory Usage                 | ~2MB                              |
| Network Intensive            | Yes                               |
| CPU Intensive                | No                                |
| Requires Elevated Privileges | No                                |
| Batch Collection             | No                                |
| Per-call Timeout             | 30s                               |

---

## Required Azure Permissions

`Reader` role at subscription scope is sufficient for enumeration.
Listing role assignments is governed by the
`Microsoft.Authorization/roleAssignments/read` permission, which
`Reader` carries (covered by `*/read`). Because collection is a pure
management-plane GET, **no Microsoft Graph / directory permission is
required** — this is the key robustness gain over the CLI list helper,
which fails outright when its Graph name-resolution call cannot complete.

---

## ESP Examples

### No Owner role grants outside the break-glass group

```esp
OBJECT all_rbac
    scope `subscription`
OBJECT_END

STATE no_unexpected_owners
    found boolean = true
    record
        field roles.*.role_definition_name string != `Owner`
    record_end
STATE_END

CTN az_role_assignment_list
    TEST all all AND
    STATE_REF no_unexpected_owners
    OBJECT_REF all_rbac
CTN_END
```

### Subscription must have at least one Reader assignment

```esp
OBJECT all_rbac
    scope `subscription`
OBJECT_END

STATE rbac_present
    found boolean = true
    role_count int >= 1
STATE_END
```

### No User principals -- groups and SPNs only (least-privilege baseline)

```esp
STATE no_user_principals
    found boolean = true
    record
        field roles.*.principal_type string != `User`
    record_end
STATE_END
```

---

## Error Conditions

| Condition                                       | Cause              | Outcome                       |
| ----------------------------------------------- | ----------------------- | ----------------------------- |
| No assignments visible                          | N/A (not an error)      | `found=false`, `role_count=0` |
| `scope` missing from OBJECT                     | Collection failed      | Error                         |
| `az` binary missing / not authenticated         | Collection failed      | Error                         |
| No `subscription` and `az account show` fails   | Collection failed      | Error (full stderr in reason) |
| Non-zero exit from `az rest` (ARM call)         | Collection failed      | Error (full stderr in reason) |
| Response has no `value` array                   | Collection failed      | Error                         |
| Stdout is not valid JSON                        | Collection failed      | Error                         |
| Incompatible CTN type                           | Contract validation failure | Error                         |

---

## Related CTN Types

| CTN Type             | Relationship                                                                                  |
| -------------------- | --------------------------------------------------------------------------------------------- |
| `az_role_assignment` | Typed cousin -- per-assignment lookup by id, with full role-definition expansion.             |
| `az_resource_group`  | Per-RG view -- assignments at RG scope appear here filtered by `roles.*.scope` containing the RG id. |
| `az_entra_group`     | Resolves the `Group` principals referenced by `roles.*.principal_id`.                         |
