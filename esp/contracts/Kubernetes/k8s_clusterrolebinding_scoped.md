# k8s_clusterrolebinding_scoped

## Overview

Per-asset, scoped-injection variant of `k8s_api_query` bound to a single
`K8s::ClusterRoleBinding`. At dispatch the scoped-injection engine fills the
OBJECT's `path` from the bound asset's `api_path` metadata, so the contract
re-queries exactly one live binding and the verdict reflects the current
subject→role grant.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET to the apiserver)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::ClusterRoleBinding`
**RECORD:** yes

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | `/apis/rbac.authorization.k8s.io/v1/clusterrolebindings/<name>` |

The single-resource GET returns one object, wrapped into a one-element `rows`
array — record paths root at `*.`.

---

## Object Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | **Yes** | Apiserver path, injected from `api_path`. Single-resource GET. |
| `label_selector` / `field_selector` / `limit` | — | No | Unused for single-resource GET. |

---

## Authentication

Same env contract as all `k8s_api_query`-based CTNs (set by
`inventory::resolver::build_env` from the bound `KubeConfig` credential):

```text
K8S_SERVER, K8S_CA_PEM_B64, K8S_INSECURE_SKIP_TLS_VERIFY,
K8S_AUTH_KIND (bearer|client_cert), K8S_BEARER_TOKEN |
K8S_CLIENT_CERT_PEM_B64 + K8S_CLIENT_KEY_PEM_B64
```

---

## Command Executed

```
GET https://<apiserver>/apis/rbac.authorization.k8s.io/v1/clusterrolebindings/<name>
Accept: application/json
```

**Sample response:**

```json
{
  "kind": "ClusterRoleBinding",
  "metadata": { "name": "cluster-admin" },
  "roleRef": { "apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": "cluster-admin" },
  "subjects": [
    { "kind": "Group", "name": "system:masters", "apiGroup": "rbac.authorization.k8s.io" }
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
| `rows` | RecordData | Yes | One-element array holding the binding object; empty `[]` on failure |

---

## RecordData Structure

| Path | Type | Example |
|------|------|---------|
| `*.metadata.name` | string | `"cluster-admin"` |
| `*.roleRef.kind` | string | `"ClusterRole"` |
| `*.roleRef.name` | string | `"cluster-admin"` |
| `*.subjects.*.kind` | string | `"Group"`, `"User"`, `"ServiceAccount"` |
| `*.subjects.*.name` | string | `"system:masters"` |

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware (`= <bad> none` idiom) | `rows` |

---

## ESP Example (CIS 5.1.7 — avoid system:masters group)

```esp
SET bindings union
    OBJECT t
        target `K8s::ClusterRoleBinding`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE no_system_masters
    found boolean = true
    record
        field *.subjects.*.name string = `system:masters` none
    record_end
STATE_END

CRI AND
    CTN k8s_clusterrolebinding_scoped
        TEST all all AND
        STATE_REF no_system_masters
        SET_REF bindings
    CTN_END
CRI_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| Binding deleted between discovery and scan | `found=false`, empty `rows` | apiserver 404; record block fails closed |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_clusterrole_scoped` | The ClusterRole referenced by `roleRef` |
| `k8s_rolebinding_scoped` | Namespaced equivalent binding |
| `k8s_api_query` | Base CTN; cluster-wide bulk inventory of all ClusterRoleBindings |
