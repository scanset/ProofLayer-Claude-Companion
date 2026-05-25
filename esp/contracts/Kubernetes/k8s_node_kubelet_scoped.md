# k8s_node_kubelet_scoped

## Overview

Per-node, scoped-injection variant of `k8s_api_query` that reads a node's
**live kubelet effective configuration** via the apiserver's configz proxy. It
binds to each `K8s::Node` but injects the node's `/proxy/configz` path, so the
`k8s_api_query` collector GETs the kubelet's running config — the API-only way
to assess CIS Kubernetes §4.2 (kubelet settings) without node-filesystem access.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET — kubelet configz proxy)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::Node`
**RECORD:** yes

> This CTN queries kubelet config, not the Node object. It does **not** cover
> §4.1 (kubelet file permissions / ownership), which requires node-filesystem
> access (SSH / node-local collectors), not the apiserver.

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("kubelet_configz_path")` | **Yes** | `/api/v1/nodes/<name>/proxy/configz` |

`kubelet_configz_path` is stamped onto every `K8s::Node` asset at discovery time
(`inventory::discover_k8s`). The configz endpoint returns a single JSON object
`{ "kubeletconfig": { ... } }` (no `items` array), which the collector wraps
into a one-element `rows` array — so record paths root at `*.kubeletconfig.<field>`.

**RBAC:** the scanning identity needs `nodes/proxy` GET. configz must also be
enabled on the kubelet (it is by default).

---

## Object Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | **Yes** | Node configz path, injected from `kubelet_configz_path`. |
| `label_selector` / `field_selector` / `limit` | — | No | Unused (single-object proxy GET). |

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
GET https://<apiserver>/api/v1/nodes/<name>/proxy/configz
Accept: application/json
```

**Sample response (abridged):**

```json
{
  "kubeletconfig": {
    "authentication": { "anonymous": { "enabled": false }, "x509": { "clientCAFile": "/etc/kubernetes/pki/ca.crt" } },
    "authorization": { "mode": "Webhook" },
    "readOnlyPort": 0,
    "makeIPTablesUtilChains": true,
    "rotateCertificates": true,
    "serverTLSBootstrap": true,
    "podPidsLimit": 4096,
    "seccompDefault": true
  }
}
```

configz returns the **fully-resolved effective config**, so defaulted fields are
present — positive assertions (`= <good> all`) work without worrying about
omitted-when-default.

---

## Collected Data Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when configz returned a body |
| `row_count` | integer | Yes | `1` for the single configz object, `0` on failure |
| `resource_version` | string | Rare | Absent — configz is not a versioned object |
| `rows` | RecordData | Yes | One-element array holding the configz object; empty `[]` on failure |

---

## RecordData Structure (`*.kubeletconfig.*`)

| Path | Type | Example | CIS |
|------|------|---------|-----|
| `*.kubeletconfig.authentication.anonymous.enabled` | boolean | `false` | 4.2.1 |
| `*.kubeletconfig.authorization.mode` | string | `"Webhook"` | 4.2.2 |
| `*.kubeletconfig.authentication.x509.clientCAFile` | string | `"/etc/kubernetes/pki/ca.crt"` | 4.2.3 |
| `*.kubeletconfig.readOnlyPort` | int | `0` | 4.2.4 |
| `*.kubeletconfig.makeIPTablesUtilChains` | boolean | `true` | 4.2.6 |
| `*.kubeletconfig.rotateCertificates` | boolean | `true` | 4.2.10 |
| `*.kubeletconfig.serverTLSBootstrap` | boolean | `true` | 4.2.11 |
| `*.kubeletconfig.podPidsLimit` | int | `4096` | 4.2.13 |
| `*.kubeletconfig.seccompDefault` | boolean | `true` | 4.2.14 |

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware; `= <good> all` for positive assertions, `= <bad> none` for negative | `rows` |

> Because configz is one row, `all` and `at_least_one` coincide for a present
> field; both **fail** when the field is absent (All/Any-over-empty is false),
> which is the intended "can't prove compliant" behavior.

---

## ESP Example (CIS 4.2.1 — anonymous auth disabled)

```esp
SET nodes union
    OBJECT t
        target `K8s::Node`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE anonymous_disabled
    found boolean = true
    record
        field *.kubeletconfig.authentication.anonymous.enabled boolean = false all
    record_end
STATE_END

CRI AND
    CTN k8s_node_kubelet_scoped
        TEST all all AND
        STATE_REF anonymous_disabled
        SET_REF nodes
    CTN_END
CRI_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| `nodes/proxy` GET denied by RBAC | `found=false`, warning | apiserver 403; record block fails closed |
| configz disabled on the kubelet | `found=false`, warning | apiserver 404 on the proxy path |
| Node removed between discovery and scan | `found=false`, empty `rows` | apiserver 404 |
| `path` missing from OBJECT | `CollectionFailed` | Node lacked `kubelet_configz_path` metadata |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_workload_scoped` | Workloads scheduled onto this node |
| `k8s_namespace_scoped` | PSA labels that complement node-level seccompDefault (4.2.14) |
| `k8s_api_query` | Base CTN; arbitrary apiserver GET incl. node proxy subresources |
