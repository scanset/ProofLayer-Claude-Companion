# k8s_networkpolicy_scoped

## Overview

Per-asset, scoped-injection variant of `k8s_api_query` bound to a single
namespaced `K8s::NetworkPolicy`. At dispatch the scoped-injection engine fills
the OBJECT's `path` from the bound asset's `api_path` metadata, so the contract
re-queries exactly one live NetworkPolicy and the verdict reflects its current
pod selector, policy types, and ingress/egress rules.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET to the apiserver)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::NetworkPolicy`
**RECORD:** yes

> For the per-namespace "does this namespace have any NetworkPolicy at all"
> check (CIS 5.3.2), use **`k8s_namespace_netpol_scoped`** instead — it binds to
> the namespace and counts policies. This CTN inspects the contents of one
> known NetworkPolicy (e.g. default-deny posture).

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | `/apis/networking.k8s.io/v1/namespaces/<ns>/networkpolicies/<name>` |

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
GET https://<apiserver>/apis/networking.k8s.io/v1/namespaces/<ns>/networkpolicies/<name>
Accept: application/json
```

**Sample response (default-deny):**

```json
{
  "kind": "NetworkPolicy",
  "metadata": { "name": "default-deny", "namespace": "app" },
  "spec": {
    "podSelector": {},
    "policyTypes": ["Ingress", "Egress"]
  }
}
```

---

## Collected Data Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when the GET returned a body |
| `row_count` | integer | Yes | `1` for a single-resource GET, `0` on failure |
| `resource_version` | string | When found | `metadata.resourceVersion` (replay-hash input) |
| `rows` | RecordData | Yes | One-element array holding the NetworkPolicy object; empty `[]` on failure |

---

## RecordData Structure

| Path | Type | Example |
|------|------|---------|
| `*.metadata.name` | string | `"default-deny"` |
| `*.metadata.namespace` | string | `"app"` |
| `*.spec.podSelector` | object | `{}` (empty = all pods in the namespace) |
| `*.spec.policyTypes.*` | string | `"Ingress"`, `"Egress"` |
| `*.spec.ingress.*.from.*.podSelector` | object | per-rule source selector |
| `*.spec.egress.*.to.*.ipBlock.cidr` | string | `"10.0.0.0/8"` |

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware (`=`, `!=`, `none`/`all` quantifiers) | `rows` |

---

## ESP Example (default-deny enforces both Ingress and Egress)

```esp
SET netpols union
    OBJECT t
        target `K8s::NetworkPolicy`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE deny_both_directions
    found boolean = true
    record
        field *.spec.policyTypes.* string = `Ingress` at_least_one
        field *.spec.policyTypes.* string = `Egress` at_least_one
    record_end
STATE_END

CRI AND
    CTN k8s_networkpolicy_scoped
        TEST all all AND
        STATE_REF deny_both_directions
        SET_REF netpols
    CTN_END
CRI_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| NetworkPolicy deleted between discovery and scan | `found=false`, empty `rows` | apiserver 404; record block fails closed |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_namespace_netpol_scoped` | Per-namespace count of NetworkPolicies (CIS 5.3.2) |
| `k8s_namespace_scoped` | The namespace this policy governs |
| `k8s_workload_scoped` | Workloads whose pods this policy's `podSelector` matches |
| `k8s_api_query` | Base CTN; cluster-wide bulk inventory of all NetworkPolicies |
