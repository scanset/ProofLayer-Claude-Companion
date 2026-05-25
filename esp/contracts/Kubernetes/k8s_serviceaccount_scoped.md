# k8s_serviceaccount_scoped

## Overview

Per-asset, scoped-injection variant of `k8s_api_query` bound to a single
namespaced `K8s::ServiceAccount`. At dispatch the scoped-injection engine fills
the OBJECT's `path` from the bound asset's `api_path` metadata, so the contract
re-queries exactly one live ServiceAccount and the verdict reflects its current
token-mount posture and attached secrets / image-pull secrets.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET to the apiserver)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::ServiceAccount`
**RECORD:** yes

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | `/api/v1/namespaces/<ns>/serviceaccounts/<name>` |

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
GET https://<apiserver>/api/v1/namespaces/<ns>/serviceaccounts/<name>
Accept: application/json
```

**Sample response:**

```json
{
  "kind": "ServiceAccount",
  "metadata": { "name": "default", "namespace": "app" },
  "automountServiceAccountToken": false,
  "secrets": [],
  "imagePullSecrets": [ { "name": "registry-cred" } ]
}
```

---

## Collected Data Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when the GET returned a body |
| `row_count` | integer | Yes | `1` for a single-resource GET, `0` on failure |
| `resource_version` | string | When found | `metadata.resourceVersion` (replay-hash input) |
| `rows` | RecordData | Yes | One-element array holding the ServiceAccount object; empty `[]` on failure |

---

## RecordData Structure

| Path | Type | Example |
|------|------|---------|
| `*.metadata.name` | string | `"default"` |
| `*.metadata.namespace` | string | `"app"` |
| `*.automountServiceAccountToken` | boolean | `false` |
| `*.secrets.*.name` | string | `"default-token-abcde"` |
| `*.imagePullSecrets.*.name` | string | `"registry-cred"` |

> `automountServiceAccountToken` is **absent** when unset (Kubernetes defaults to
> mounting). For a "token must not auto-mount" control assert
> `... automountServiceAccountToken boolean = false all` — All-over-empty is false,
> so the absent (defaults-to-mount) case correctly fails.

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware (`=`, `!=`, `none`/`all` quantifiers) | `rows` |

---

## ESP Example (ServiceAccount must opt out of token auto-mount)

```esp
SET serviceaccounts union
    OBJECT t
        target `K8s::ServiceAccount`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE token_not_automounted
    found boolean = true
    record
        field *.automountServiceAccountToken boolean = false all
    record_end
STATE_END

CRI AND
    CTN k8s_serviceaccount_scoped
        TEST all all AND
        STATE_REF token_not_automounted
        SET_REF serviceaccounts
    CTN_END
CRI_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| ServiceAccount deleted between discovery and scan | `found=false`, empty `rows` | apiserver 404; record block fails closed |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_rolebinding_scoped` | Bindings that grant this ServiceAccount a Role |
| `k8s_workload_scoped` | Workloads whose pods run as this ServiceAccount |
| `k8s_namespace_scoped` | The namespace containing this ServiceAccount |
| `k8s_api_query` | Base CTN; cluster-wide bulk inventory of all ServiceAccounts |
