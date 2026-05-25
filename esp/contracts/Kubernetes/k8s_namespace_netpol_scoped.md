# k8s_namespace_netpol_scoped

## Overview

Per-namespace, scoped-injection variant of `k8s_api_query` that answers a
single question: **does this namespace have any NetworkPolicy defined?** It
binds to each `K8s::Namespace` but injects the namespace's NetworkPolicy
**list** path (not the namespace object's own path), so the `k8s_api_query`
collector returns `row_count` = the number of NetworkPolicies in that namespace.
The policy then asserts `row_count >= 1`. This is the CIS 5.3.2 check.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET — list mode)
**Executor:** `K8sApiQueryExecutor` (scalar STATE; `row_count` gate)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::Namespace`
**RECORD:** not required (verdict is the scalar `row_count`)

> This CTN counts policies; it does not inspect their contents. To assert on a
> specific policy's rules (e.g. default-deny), use `k8s_networkpolicy_scoped`.

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("netpol_list_path")` | **Yes** | `/apis/networking.k8s.io/v1/namespaces/<ns>/networkpolicies` (list) |

`netpol_list_path` is stamped onto every `K8s::Namespace` asset at discovery
time (`inventory::discover_k8s`, alongside the namespace's own `api_path`).
Unlike the single-resource CTNs, this path is a **list** endpoint — the
collector returns every NetworkPolicy in the namespace as `rows`, and
`row_count` is the count.

---

## Object Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | **Yes** | NetworkPolicy list path for the namespace, injected from `netpol_list_path`. |
| `label_selector` / `field_selector` / `limit` | — | No | Available (list mode) but unused by CIS 5.3.2. |

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
GET https://<apiserver>/apis/networking.k8s.io/v1/namespaces/<ns>/networkpolicies
Accept: application/json
```

**Sample response (list):**

```json
{
  "kind": "NetworkPolicyList",
  "items": [
    { "metadata": { "name": "default-deny", "namespace": "app" }, "spec": { "podSelector": {}, "policyTypes": ["Ingress", "Egress"] } }
  ]
}
```

A namespace with no policies returns an empty `items` array → `row_count = 0` → fail.

---

## Collected Data Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when the list call succeeded (even with zero items) |
| `row_count` | integer | Yes | Number of NetworkPolicies in the namespace |
| `resource_version` | string | When found | List `metadata.resourceVersion` (replay-hash input) |
| `rows` | RecordData | Yes | Array of NetworkPolicy objects (each item as returned); `[]` when none |

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware over `rows` (optional; CIS 5.3.2 does not need it) | `rows` |

---

## ESP Example (CIS 5.3.2 — every namespace has a policy)

```esp
SET namespaces union
    OBJECT t
        target `K8s::Namespace`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE has_network_policy
    found boolean = true
    row_count int >= 1
STATE_END

CRI AND
    CTN k8s_namespace_netpol_scoped
        TEST all all AND
        STATE_REF has_network_policy
        SET_REF namespaces
    CTN_END
CRI_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| Namespace has zero NetworkPolicies | `found=true`, `row_count=0` | Not an error — the `row_count >= 1` assertion fails (intended) |
| Namespace deleted between discovery and scan | `found=false` | apiserver 404 on the list path |
| `path` missing from OBJECT | `CollectionFailed` | Namespace lacked `netpol_list_path` metadata |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_networkpolicy_scoped` | Inspects the contents of an individual NetworkPolicy |
| `k8s_namespace_scoped` | Inspects the namespace object itself (PSA labels, etc.) |
| `k8s_api_query` | Base CTN; arbitrary apiserver list/get |
