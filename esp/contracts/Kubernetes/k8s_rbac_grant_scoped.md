# k8s_rbac_grant_scoped

## Overview

Per-asset, scoped-injection CTN bound to a single `K8s::ClusterRole` that
answers a **correlated** RBAC question generic record checks cannot: *does any
single rule grant a forbidden (apiGroup × resource × verb) combination
together?* It reuses the `k8s_api_query` collector (which GETs the bound
ClusterRole and returns its object as the single `rows` element) but pairs it
with a dedicated `K8sRbacGrantExecutor` that applies RBAC-aware grant matching
in code. This drives CIS Kubernetes 5.1.4 / 5.1.9–5.1.13 ("minimize access to
create pods / persistentvolumes / nodes-proxy / CSR-approval / webhook-configs /
SA-token-creation").

**Pattern:** Scoped injection over `k8s_api_query` collector + custom executor
**Executor:** `K8sRbacGrantExecutor` (correlated rule matching; no record block)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::ClusterRole`
**RECORD:** no (the executor walks `rules[]` directly)

> **Why not a `record` block?** A `record field *.rules.*.resources.* = pods none`
> plus `*.rules.*.verbs.* = create none` evaluate each path *independently*, so a
> role with one rule granting `get` on pods and a *different* rule granting
> `create` on configmaps would false-fail. This executor checks `resource` and
> `verb` co-occurrence **within the same rule**, with `*` wildcard awareness.

> **Scope:** registered against `K8s::ClusterRole` (cluster-wide blast radius).
> A namespaced-`Role` variant is a trivial follow-up (one more projection +
> registration reusing this executor) — not yet authored.

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | `/apis/rbac.authorization.k8s.io/v1/clusterroles/<name>` |

Same single-object GET as `k8s_clusterrole_scoped`; the response is wrapped into
a one-element `rows` array. The executor reads `rows[0].rules[]`.

---

## Object Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | **Yes** | ClusterRole object path, injected from `api_path`. |
| `label_selector` / `field_selector` / `limit` | — | No | Unused (single-object GET). |

---

## Policy-Authored Parameters (STATE scalar fields)

The forbidden grant is declared in the STATE block — these are **inputs to the
executor**, not assertions against collected data:

| STATE Field | Type | Required | Meaning |
|-------------|------|----------|---------|
| `found` | boolean | Yes | Gate: the ClusterRole must have been fetched (`= true`). |
| `forbidden_resource` | string | **Yes** | Resource(s) that must not be granted. Comma-separated for a set (e.g. `validatingwebhookconfigurations,mutatingwebhookconfigurations`). Sub-resources allowed (`nodes/proxy`, `serviceaccounts/token`). |
| `forbidden_verb` | string | **Yes** | Verb(s) that must not be granted. Comma-separated for a set (e.g. `create,update,patch,delete`). |
| `forbidden_apigroup` | string | No | API group constraint. Omit for core (`""`) resources where the resource name is unambiguous; set for non-core (e.g. `certificates.k8s.io`, `admissionregistration.k8s.io`). |

---

## Matching Semantics

A rule is a **violation** when **all** hold:

- **resource:** `rule.resources` contains any `forbidden_resource` entry **or** `*`
- **verb:** `rule.verbs` contains any `forbidden_verb` entry **or** `*`
- **apiGroup:** `forbidden_apigroup` unset, **or** `rule.apiGroups` contains it **or** `*`

The object PASSES when `found == true` **and** no rule violates; it FAILS the
moment one rule does. The TEST `item_check` (`all`) then requires every bound
ClusterRole to pass.

> Roles that legitimately hold the grant (controllers, `cluster-admin`) will
> fail and surface as evidence for review/exemption — the intended posture for
> these "minimize access" (manual) controls.

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

## Collected Data Fields

| Field | Type | Always Present | Source |
|-------|------|----------------|--------|
| `found` | boolean | Yes | `true` when the GET returned a body |
| `row_count` | integer | Yes | `1` for the single-resource GET, `0` on failure |
| `rows` | RecordData | Yes | One-element array holding the ClusterRole object; empty `[]` on failure |

The executor reads `rows` via `RecordData::as_json_value()` and walks `rules[]`.

---

## ESP Example (CIS 5.1.4 — minimize access to create pods)

```esp
SET clusterroles union
    OBJECT t
        target `K8s::ClusterRole`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE no_create_pods
    found boolean = true
    forbidden_resource string = `pods`
    forbidden_verb string = `create`
STATE_END

CRI AND
    CTN k8s_rbac_grant_scoped
        TEST all all AND
        STATE_REF no_create_pods
        SET_REF clusterroles
    CTN_END
CRI_END
```

Multi-resource / multi-verb example (CIS 5.1.12 — webhook configs):

```esp
STATE no_webhook_writes
    found boolean = true
    forbidden_resource string = `validatingwebhookconfigurations,mutatingwebhookconfigurations`
    forbidden_verb string = `create,update,patch,delete`
    forbidden_apigroup string = `admissionregistration.k8s.io`
STATE_END
```

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| `forbidden_resource` or `forbidden_verb` missing | `Fail` | The executor requires both STATE fields |
| ClusterRole deleted between discovery and scan | object fails (`found != true`) | apiserver 404 |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| `rows` not RecordData | object fails | Rules not evaluable; fails closed |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_clusterrole_scoped` | Generic wildcard/field checks on the same ClusterRole object |
| `k8s_clusterrolebinding_scoped` | Which subjects receive this ClusterRole |
| `k8s_api_query` | Base collector; cluster-wide bulk inventory of ClusterRoles |
