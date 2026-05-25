# k8s_clusterrole_scoped

## Overview

Per-asset, scoped-injection variant of `k8s_api_query` bound to a single
`K8s::ClusterRole`. At dispatch the scoped-injection engine
(`prooflayer-2 inventory::inject`) fills the OBJECT's `path` from the bound
asset's `api_path` metadata, so the contract re-queries exactly one live
ClusterRole and the verdict reflects current cluster RBAC.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET to the apiserver)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::ClusterRole`
**RECORD:** yes

---

## Scoped Injection

This CTN is never authored with literal inputs. The ESP policy declares a
placeholder OBJECT with `behavior inject_from_bound_asset`; the dispatcher
walks the asset graph to each bound `K8s::ClusterRole` and projects one
OBJECT per asset.

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | `/apis/rbac.authorization.k8s.io/v1/clusterroles/<name>` |

`api_path` is stamped onto every `K8s::ClusterRole` asset at discovery time
(`inventory::discover_k8s::k8s_api_path`). A single-resource GET returns one
object (no `items` array), which the collector wraps into a one-element
`rows` array — so record paths are rooted at `*.` (the first/only row).

---

## Object Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | **Yes** | Apiserver path, injected from `api_path`. Single-resource GET. |
| `label_selector` | string | No | `?labelSelector=` filter (unused for single-resource GET). |
| `field_selector` | string | No | `?fieldSelector=` filter (unused for single-resource GET). |
| `limit` | int | No | `?limit=` page size (unused for single-resource GET). |

If `path` is absent the collector returns `CollectionFailed`.

---

## Authentication

The collector reads the apiserver endpoint and credential from process env
(set by `inventory::resolver::build_env` from the bound `KubeConfig`
credential) — there is no kubeconfig YAML at runtime, and the K8s flavor
(local / AKS / EKS) is transparent at this layer.

```text
K8S_SERVER                  apiserver URL (no trailing slash)
K8S_CA_PEM_B64              base64 cluster CA PEM (optional if skip-verify)
K8S_INSECURE_SKIP_TLS_VERIFY  "true" | "false" (default false)
K8S_AUTH_KIND               "bearer" | "client_cert"
K8S_BEARER_TOKEN            required when auth_kind=bearer
K8S_CLIENT_CERT_PEM_B64     required when auth_kind=client_cert
K8S_CLIENT_KEY_PEM_B64      required when auth_kind=client_cert
```

Exec auth providers (`kubelogin`, `aws-iam-authenticator`) are rejected at
credential-creation time and cannot reach this collector.

---

## Command Executed

```
GET https://<apiserver>/apis/rbac.authorization.k8s.io/v1/clusterroles/<name>
Accept: application/json
```

**Sample response (single object):**

```json
{
  "apiVersion": "rbac.authorization.k8s.io/v1",
  "kind": "ClusterRole",
  "metadata": { "name": "view" },
  "rules": [
    { "apiGroups": [""], "resources": ["pods", "services"], "verbs": ["get", "list", "watch"] }
  ]
}
```

---

## Collected Data Fields

### Scalar Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when the GET returned a body |
| `row_count` | integer | Yes | `1` for a single-resource GET, `0` on failure |
| `resource_version` | string | When found | `metadata.resourceVersion` (replay-hash input) |

### RecordData Field

| Field | Type | Always Present | Description |
|-------|------|----------------|-------------|
| `rows` | RecordData | Yes | One-element array holding the ClusterRole object; empty `[]` on failure |

---

## RecordData Structure

Record checks are rooted at the `rows` array (`*.` = the single object).

| Path | Type | Example |
|------|------|---------|
| `*.metadata.name` | string | `"view"` |
| `*.rules.*.apiGroups.*` | string | `""`, `"apps"`, `"*"` |
| `*.rules.*.resources.*` | string | `"pods"`, `"secrets"`, `"*"` |
| `*.rules.*.verbs.*` | string | `"get"`, `"escalate"`, `"*"` |

---

## State Fields

### Scalar State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |

### Record Checks

| Maps To | Description |
|---------|-------------|
| `rows` | Wildcard-aware deep inspection of the ClusterRole's `rules`. Use the `none` quantifier with a bad value (`= <bad> none`) for "minimize" controls — passes when no expanded element matches and is vacuously true on absent/empty fields. |

---

## ESP Example (CIS 5.1.3 — minimize wildcard use)

```esp
SET clusterroles union
    OBJECT t
        target `K8s::ClusterRole`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE no_wildcard_rules
    found boolean = true
    record
        field *.rules.*.apiGroups.* string = `*` none
        field *.rules.*.resources.* string = `*` none
        field *.rules.*.verbs.* string = `*` none
    record_end
STATE_END

CRI AND
    CTN k8s_clusterrole_scoped
        TEST all all AND
        STATE_REF no_wildcard_rules
        SET_REF clusterroles
    CTN_END
CRI_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| ClusterRole deleted between discovery and scan | `found=false`, empty `rows` | apiserver 404; record block fails closed |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_clusterrolebinding_scoped` | Bindings that grant this ClusterRole to subjects |
| `k8s_role_scoped` | Namespaced equivalent of the same rule schema |
| `k8s_api_query` | Base CTN; cluster-wide bulk inventory of all ClusterRoles |
