# k8s_namespace_scoped

## Overview

Per-asset, scoped-injection variant of `k8s_api_query` bound to a single
`K8s::Namespace`. At dispatch the scoped-injection engine fills the OBJECT's
`path` from the bound asset's `api_path` metadata, so the contract re-queries
exactly one live namespace and the verdict reflects its current labels and
status — including the Pod Security Admission labels that govern workload
admission in that namespace.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET to the apiserver)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::Namespace`
**RECORD:** yes

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | `/api/v1/namespaces/<name>` |

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
GET https://<apiserver>/api/v1/namespaces/<name>
Accept: application/json
```

**Sample response:**

```json
{
  "kind": "Namespace",
  "metadata": {
    "name": "app",
    "labels": {
      "kubernetes.io/metadata.name": "app",
      "pod-security.kubernetes.io/enforce": "restricted",
      "pod-security.kubernetes.io/enforce-version": "latest"
    }
  },
  "status": { "phase": "Active" }
}
```

---

## Collected Data Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when the GET returned a body |
| `row_count` | integer | Yes | `1` for a single-resource GET, `0` on failure |
| `resource_version` | string | When found | `metadata.resourceVersion` (replay-hash input) |
| `rows` | RecordData | Yes | One-element array holding the namespace object; empty `[]` on failure |

---

## RecordData Structure

| Path | Type | Example |
|------|------|---------|
| `*.metadata.name` | string | `"app"` |
| `*.metadata.labels.pod-security.kubernetes.io/enforce` | string | `"restricted"`, `"baseline"`, `"privileged"` |
| `*.metadata.labels.pod-security.kubernetes.io/audit` | string | `"restricted"` |
| `*.metadata.labels.pod-security.kubernetes.io/warn` | string | `"restricted"` |
| `*.status.phase` | string | `"Active"` |

> Label keys containing dots/slashes (e.g. `pod-security.kubernetes.io/enforce`)
> are map keys, not path separators — the validator treats the segment after the
> final addressable map as a literal key.

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware (`=`, `!=`, `none`/`all` quantifiers) | `rows` |

---

## ESP Example (namespace enforces restricted Pod Security Admission)

```esp
SET namespaces union
    OBJECT t
        target `K8s::Namespace`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE psa_restricted
    found boolean = true
    record
        field *.metadata.labels.pod-security.kubernetes.io/enforce string = `restricted` all
    record_end
STATE_END

CRI AND
    CTN k8s_namespace_scoped
        TEST all all AND
        STATE_REF psa_restricted
        SET_REF namespaces
    CTN_END
CRI_END
```

> The `all` quantifier asserts the label is present **and** equals `restricted`
> (All-over-empty is false, so a missing label fails — the intended behavior for
> a "must be set" control).

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| Namespace deleted between discovery and scan | `found=false`, empty `rows` | apiserver 404; record block fails closed |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_workload_scoped` | Workloads admitted under this namespace's PSA labels |
| `k8s_serviceaccount_scoped` | ServiceAccounts in this namespace |
| `k8s_api_query` | Base CTN; cluster-wide bulk inventory of all namespaces |
