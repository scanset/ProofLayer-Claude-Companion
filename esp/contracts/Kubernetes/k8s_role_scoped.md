# k8s_role_scoped

## Overview

Per-asset, scoped-injection variant of `k8s_api_query` bound to a single
namespaced `K8s::Role`. At dispatch the scoped-injection engine fills the
OBJECT's `path` from the bound asset's `api_path` metadata, so the contract
re-queries exactly one live Role and the verdict reflects current namespace
RBAC.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET to the apiserver)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::Role`
**RECORD:** yes

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | `/apis/rbac.authorization.k8s.io/v1/namespaces/<ns>/roles/<name>` |

The namespaced path carries the Role's namespace, stamped at discovery
(`inventory::discover_k8s::k8s_api_path`). The single-resource GET returns one
object, wrapped into a one-element `rows` array — record paths root at `*.`.

---

## Object Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | **Yes** | Apiserver path, injected from `api_path`. Single-resource GET. |
| `label_selector` / `field_selector` / `limit` | — | No | Unused for single-resource GET. |

If `path` is absent the collector returns `CollectionFailed`.

---

## Authentication

Same env contract as all `k8s_api_query`-based CTNs (set by
`inventory::resolver::build_env` from the bound `KubeConfig` credential):

```text
K8S_SERVER, K8S_CA_PEM_B64, K8S_INSECURE_SKIP_TLS_VERIFY,
K8S_AUTH_KIND (bearer|client_cert), K8S_BEARER_TOKEN |
K8S_CLIENT_CERT_PEM_B64 + K8S_CLIENT_KEY_PEM_B64
```

No kubeconfig YAML at runtime; flavor (local / AKS / EKS) is transparent.

---

## Command Executed

```
GET https://<apiserver>/apis/rbac.authorization.k8s.io/v1/namespaces/<ns>/roles/<name>
Accept: application/json
```

**Sample response:**

```json
{
  "kind": "Role",
  "metadata": { "name": "configmap-reader", "namespace": "app" },
  "rules": [
    { "apiGroups": [""], "resources": ["configmaps"], "verbs": ["get", "list"] }
  ]
}
```

---

## Collected Data Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when the GET returned a body |
| `row_count` | integer | Yes | `1` for a single-resource GET, `0` on failure |
| `resource_version` | string | When found | `metadata.resourceVersion` (replay-hash input) |
| `rows` | RecordData | Yes | One-element array holding the Role object; empty `[]` on failure |

---

## RecordData Structure

| Path | Type | Example |
|------|------|---------|
| `*.metadata.name` | string | `"configmap-reader"` |
| `*.metadata.namespace` | string | `"app"` |
| `*.rules.*.apiGroups.*` | string | `""`, `"apps"`, `"*"` |
| `*.rules.*.resources.*` | string | `"configmaps"`, `"secrets"`, `"*"` |
| `*.rules.*.verbs.*` | string | `"get"`, `"escalate"`, `"*"` |

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware (`= <bad> none` idiom) | `rows` |

---

## ESP Example (minimize wildcard use in Roles)

```esp
SET roles union
    OBJECT t
        target `K8s::Role`
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
    CTN k8s_role_scoped
        TEST all all AND
        STATE_REF no_wildcard_rules
        SET_REF roles
    CTN_END
CRI_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| Role deleted between discovery and scan | `found=false`, empty `rows` | apiserver 404; record block fails closed |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_rolebinding_scoped` | Bindings that grant this Role to subjects |
| `k8s_clusterrole_scoped` | Cluster-scoped equivalent of the same rule schema |
| `k8s_api_query` | Base CTN; cluster-wide bulk inventory of all Roles |
