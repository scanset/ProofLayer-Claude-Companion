# m365_group_scoped

## Overview

Scoped-injection variant of [`m365_graph_query`](m365_graph_query.md). The collector, command(s), collected data, and state fields are **identical to the base CTN** — this variant only changes *how the `OBJECT` is populated*: at dispatch the `inject_from_bound_asset` placeholder is replaced by one concrete `OBJECT` per resolved asset, filled from that asset's metadata. One policy file scans every matching resource, naming none.

**Binds to:** `M365::Group` — depth-0 (N=1) when bound directly to the asset; fans out via the `link` relation when bound to a container.

---

## Injection / Projection

The `m365_group_scoped` projection fills the injected `OBJECT` fields from the bound asset's metadata:

| OBJECT field | Source | Required |
| ------------ | ------ | -------- |
| `path` | literal `groups` | **Yes** |
| `resource_id` | `metadata.provider_id` | **Yes** |

`target_asset_type`: `M365::Group`. No hardcoded resource id appears in the policy — the binding determines scope.

**Placeholder (in the policy `DEF`):**

```esp
SET groups union
    OBJECT t
        target `M365::Group`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END
```

---

## Object Fields

| Field    | Type    | Required | Description                                                                       | Example                                                            |
| -------- | ------- | -------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `path`   | string  | **Yes**  | Graph collection path. Leading slash optional.                                    | `/users`, `groups`, `identity/conditionalAccess/policies`         |
| `select` | string  | No       | OData `$select` clause — comma-separated field list. Reduces response size.       | `id,displayName,userPrincipalName,accountEnabled`                  |
| `filter` | string  | No       | OData `$filter` expression.                                                       | `accountEnabled eq true`                                           |
| `expand` | string  | No       | OData `$expand` clause for related-resource expansion.                            | `memberOf`                                                         |
| `top`    | integer | No       | Per-page result count for `$top`. Default 999. Graph clamps per resource type.    | `999`                                                              |

---

## Commands Executed

### Command 1: GET https://graph.microsoft.com/v1.0/{path}

The collector issues a `GET` with a Graph bearer in the `Authorization`
header. Pagination follows `@odata.nextLink` URLs (each fully formed)
until exhausted or the `MAX_ROWS` cap is hit.

```
GET https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName&$top=999
Authorization: Bearer <token>
ConsistencyLevel: eventual
```

The `ConsistencyLevel: eventual` header is required for advanced query
support (e.g. `$filter` with `endsWith`, `$count`). It's harmless on
queries that don't need it.

### Authentication

The collector trades the `AZURE_CLIENT_SECRET` for a Graph bearer:

```
POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

client_id={AZURE_CLIENT_ID}&
client_secret={AZURE_CLIENT_SECRET}&
grant_type=client_credentials&
scope=https://graph.microsoft.com/.default
```

Tokens are cached for their lifetime (typically 3600s) with a 60s
refresh margin. The app registration must grant the relevant Graph
*application permissions* with admin consent — see the Entra app
registration setup guide in `docs/m365/app-registration.md`.

---

## Required Environment

| Variable              | Purpose                                                |
| --------------------- | ------------------------------------------------------ |
| `AZURE_TENANT_ID`     | Entra tenant GUID — used in the token endpoint URL.   |
| `AZURE_CLIENT_ID`     | App registration's application (client) ID.            |
| `AZURE_CLIENT_SECRET` | App registration's client secret.                      |

Set by `inventory::resolver::build_env` for any `AzureSpn` credential.
The same credential the `az_resource_graph_query` CTN uses — only the
token audience differs (`graph.microsoft.com` vs `management.azure.com`).

---

## State Fields (returned)

| Field       | Type       | Description                                              |
| ----------- | ---------- | -------------------------------------------------------- |
| `found`     | boolean    | Always true on success.                                  |
| `row_count` | integer    | Total rows returned across all pagination fetches.       |
| `rows`      | RecordData | JSON array of row objects from Graph.                    |

Each row in `rows` is the unmodified Graph object (after `$select`
projection if specified). The discovery layer iterates the array and
maps each row to an asset record.

---

## Examples

```
# All users in the tenant
path: /users
select: id,displayName,userPrincipalName,accountEnabled

# Just enabled users
path: /users
filter: accountEnabled eq true
select: id,displayName,userPrincipalName

# Conditional access policies
path: identity/conditionalAccess/policies

# Intune managed devices
path: deviceManagement/managedDevices

# Sensitivity labels (Purview)
path: security/sensitivityLabels
```

---

## Failure Modes

| Symptom                                       | Likely cause                                                                        |
| --------------------------------------------- | ----------------------------------------------------------------------------------- |
| HTTP 401 from Graph                           | Token expired (collector auto-refreshes), or app permission not granted.            |
| HTTP 403 from Graph                           | App permission granted but admin consent not provided.                              |
| HTTP 400 with "Bad Request"                   | Malformed `$filter` — check OData syntax.                                            |
| HTTP 429 (Throttled)                          | Tenant rate limit. Retry with backoff; collector does not auto-retry today.         |
| `AZURE_TENANT_ID not set` error               | Credential not resolved via `build_env`. Check the credential is `AzureSpn` kind.   |
| Row truncation at 100,000                     | Tenant has more than 100k of this resource type. Apply `$filter` to narrow.         |

