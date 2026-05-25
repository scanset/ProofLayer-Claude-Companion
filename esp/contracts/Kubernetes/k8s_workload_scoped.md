# k8s_workload_scoped

## Overview

Per-asset, scoped-injection variant of `k8s_api_query` bound to a single
`K8s::Workload` (Deployment, DaemonSet, StatefulSet, ReplicaSet, Job, CronJob,
or bare/static Pod). At dispatch the scoped-injection engine fills the OBJECT's
`path` from the bound asset's `api_path` metadata, so the contract re-queries
exactly one live workload and the verdict reflects the current pod template.

**Pattern:** Scoped injection over `k8s_api_query` (HTTPS GET to the apiserver)
**Executor:** `K8sApiQueryExecutor` (scalar STATE + RecordData record checks)
**Base CTN:** `k8s_api_query`
**Target asset type:** `K8s::Workload`
**RECORD:** yes

---

## Scoped Injection

| Projected Field | Source | Required | Resolves To |
|-----------------|--------|----------|-------------|
| `path` | `SelfMetadata("api_path")` | **Yes** | group/plural keyed by workload kind (see below) |

`api_path` is computed per workload at discovery
(`inventory::discover_k8s::k8s_api_path`) from the workload kind:

| Workload kind | Apiserver path |
|---------------|----------------|
| Deployment | `/apis/apps/v1/namespaces/<ns>/deployments/<name>` |
| DaemonSet | `/apis/apps/v1/namespaces/<ns>/daemonsets/<name>` |
| StatefulSet | `/apis/apps/v1/namespaces/<ns>/statefulsets/<name>` |
| ReplicaSet | `/apis/apps/v1/namespaces/<ns>/replicasets/<name>` |
| Job | `/apis/batch/v1/namespaces/<ns>/jobs/<name>` |
| CronJob | `/apis/batch/v1/namespaces/<ns>/cronjobs/<name>` |
| Pod / StaticPod | `/api/v1/namespaces/<ns>/pods/<name>` |

The single-resource GET returns one object, wrapped into a one-element `rows`
array — record paths root at `*.`.

> **Pod-template path note:** Controller workloads (Deployment, etc.) carry the
> pod spec under `spec.template.spec`. A bare **Pod** carries it under `spec`
> directly (no `template`). The §5 policies target `*.spec.template.spec.*`,
> matching controller workloads; for bare-Pod coverage author a parallel field
> rooted at `*.spec.*`.

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
GET https://<apiserver>/apis/apps/v1/namespaces/<ns>/deployments/<name>
Accept: application/json
```

**Sample response (abridged Deployment):**

```json
{
  "kind": "Deployment",
  "metadata": { "name": "web", "namespace": "app" },
  "spec": {
    "template": {
      "spec": {
        "hostPID": false,
        "hostNetwork": false,
        "containers": [
          {
            "name": "web",
            "ports": [ { "containerPort": 8080 } ],
            "securityContext": {
              "privileged": false,
              "allowPrivilegeEscalation": false,
              "capabilities": { "add": ["NET_BIND_SERVICE"] }
            }
          }
        ],
        "volumes": [ { "name": "data", "emptyDir": {} } ]
      }
    }
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
| `rows` | RecordData | Yes | One-element array holding the workload object; empty `[]` on failure |

---

## RecordData Structure (controller pod template)

| Path | Type | Example |
|------|------|---------|
| `*.metadata.name` | string | `"web"` |
| `*.spec.template.spec.hostPID` | boolean | `false` |
| `*.spec.template.spec.hostIPC` | boolean | `false` |
| `*.spec.template.spec.hostNetwork` | boolean | `false` |
| `*.spec.template.spec.securityContext.windowsOptions.hostProcess` | boolean | `false` |
| `*.spec.template.spec.containers.*.securityContext.privileged` | boolean | `false` |
| `*.spec.template.spec.containers.*.securityContext.allowPrivilegeEscalation` | boolean | `false` |
| `*.spec.template.spec.containers.*.securityContext.capabilities.add.*` | string | `"NET_RAW"` |
| `*.spec.template.spec.containers.*.securityContext.windowsOptions.hostProcess` | boolean | `false` |
| `*.spec.template.spec.containers.*.ports.*.hostPort` | int | `8080` |
| `*.spec.template.spec.volumes.*.hostPath.path` | string | `"/var/run/docker.sock"` |

---

## State Fields

| State Field | Type | Allowed Operations | Maps To |
|-------------|------|--------------------|---------|
| `found` | boolean | `=`, `!=` | `found` |
| `row_count` | int | `=`, `!=`, `>=`, `>`, `<`, `<=` | `row_count` |
| `record` | — | wildcard-aware (`= <bad> none` idiom; `starts`, `int >` for presence) | `rows` |

---

## ESP Example (CIS 5.2.2 — minimize privileged containers)

```esp
SET workloads union
    OBJECT t
        target `K8s::Workload`
        link `contains`
        behavior inject_from_bound_asset
    OBJECT_END
SET_END

STATE no_privileged_containers
    found boolean = true
    record
        field *.spec.template.spec.containers.*.securityContext.privileged boolean = true none
    record_end
STATE_END

CRI AND
    CTN k8s_workload_scoped
        TEST all all AND
        STATE_REF no_privileged_containers
        SET_REF workloads
    CTN_END
CRI_END
```

Presence-style checks use the same `none` quantifier with an operator that
only matches set values — e.g. hostPath via `... hostPath.path string starts \`/\` none`
(absolute paths begin with `/`), or hostPort via `... ports.*.hostPort int > 0 none`.

---

## Error Conditions

| Condition | Outcome | Notes |
|-----------|---------|-------|
| Workload deleted between discovery and scan | `found=false`, empty `rows` | apiserver 404; record block fails closed |
| `path` missing from OBJECT | `CollectionFailed` | Scoped injection failed to project `api_path` |
| Endpoint env unset / bad credential | `found=false`, warning | `resolve_endpoint` / client build failed |
| Bare Pod with `spec.template`-rooted check | passes vacuously | Pod spec is not under `template`; author `*.spec.*` for Pods |
| Incompatible CTN type | `CtnContractValidation` | Collector validates `ctn_type == "k8s_api_query"` |

---

## Related CTN Types

| CTN | Relationship |
|-----|--------------|
| `k8s_serviceaccount_scoped` | The ServiceAccount the workload's pods run as |
| `k8s_namespace_scoped` | The namespace whose Pod Security Admission governs admission |
| `k8s_api_query` | Base CTN; cluster-wide bulk inventory of all workloads |
