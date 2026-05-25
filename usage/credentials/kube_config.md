# `kube_config`

Network-reachable Kubernetes cluster credential. Powers the
`/api/inventory/discover/k8s/local` discovery route, the container-exec
scan channel (container posture scanning), and the future AKS / EKS
preflight paths.

Prooflayer's VM and the target K8s cluster are **always on different
machines** — there is no "ambient kubeconfig on disk" path. The
credential carries every byte needed to talk to the apiserver: URL,
CA bundle, and one of {bearer token, client certificate + key}.

## What it represents

An identity in a single Kubernetes cluster (the one the credential's
`server` URL points at). The recommended provisioning pattern is a
`ServiceAccount` bound to a custom `ClusterRole`. **The RBAC behind
that SA determines what the credential can do — discovery, scanning,
or both.** The credential *shape* is identical in every case (server +
CA + bearer/cert); only the SA's permissions differ.

## Discovery vs scanning — two privilege tiers

This is the key operational decision when provisioning a K8s cred.
Discovery and scanning need different permissions, and you choose how
to split them:

| Capability | RBAC required | Sensitivity |
|---|---|---|
| **Discovery** (walk the API, build the asset graph) | `get/list/watch` on namespaces, nodes, serviceaccounts, pods, deployments, statefulsets, daemonsets, jobs, cronjobs, roles, rolebindings, clusterroles, clusterrolebindings | Read-only |
| **Scanning** (exec into containers via the container-exec channel) | **+ `get` and `create` on `pods/exec`** | High — effectively "run arbitrary commands in any pod in scope" |

Two deployment patterns:

- **One SA, both tiers** — bind a single SA to a ClusterRole that has
  the discovery rules *plus* the `pods/exec` rule. One `kube_config`
  cred discovers and scans. Simplest; fewer creds to manage.
- **Two SAs, two creds** (recommended for CMMC/FedRAMP) — a read-only
  `prooflayer-discoverer` SA for continuous inventory, and a separate
  exec-capable `prooflayer-scanner` SA for posture scans. Store each as
  its own `kube_config` cred at the same cluster. The discovery cred is
  *provably incapable of code execution* — it 403s on `pods/exec` by
  construction. Strong SSP story: inventory runs with a token that
  cannot exec; scans use a separately-bound, audited credential.

> **`pods/exec` needs BOTH `get` and `create`.** The widely-documented
> `create pods/exec` only covers the legacy SPDY/POST transport that
> classic `kubectl exec` uses. Prooflayer's container-exec channel (and
> modern kubectl's WebSocket executor) issues a **GET** WebSocket-upgrade
> request, which K8s authorizes as `get pods/exec`. Granting only
> `create` yields `cannot get resource "pods/exec"` 403s. Grant both.

Secrets and ConfigMap *contents* are deliberately **excluded** from
both tiers — Prooflayer needs neither to discover the asset graph or
to run container posture checks.

## Payload fields

| Field                       | Required | Description                                                                                  |
|---                          |---       |---                                                                                           |
| `cluster_name`              | yes      | Display label. Not auth-bearing; shown in the UI and stamped into asset `metadata.flavor`     |
| `server`                    | yes      | Apiserver URL (`https://host:port`). Trailing slashes stripped at sweep time                  |
| `ca_bundle_pem`             | yes\*    | PEM-encoded cluster CA bundle. Required unless `insecure_skip_tls_verify` is true              |
| `insecure_skip_tls_verify`  | no       | Default false. Set true only for development clusters — disables CA validation entirely        |
| `auth.kind`                 | yes      | `bearer` or `client_cert`                                                                     |
| `auth.token`                | yes (bearer)      | Bearer token string — typically a long-lived ServiceAccount token                  |
| `auth.cert_pem`             | yes (client_cert) | PEM-encoded client certificate                                                       |
| `auth.key_pem`              | yes (client_cert) | PEM-encoded client private key                                                       |

Exec auth providers (`kubelogin`, `aws-iam-authenticator`, etc.) and
file-path references to certs/keys are **not supported** — the
credential must be fully self-contained. The server-side parse
endpoint rejects both with precise error messages.

## Metadata fields (non-secret, operator-set)

| Key       | Purpose                                                                       |
|---        |---                                                                            |
| `notes`   | Free-form context — "kind-test dev cluster", "prod-us-east-1 AKS", etc.        |

The auth surface lives in the payload, not metadata.

## How to provision (recommended: service-account token)

Run this against the target cluster with your existing `kubectl` admin
access. The discovery rules are the read-only base; the `pods/exec`
rule (commented) is what upgrades the identity to scan-capable.

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prooflayer-scanner
  namespace: prooflayer-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prooflayer-scanner
rules:
# ---- Discovery (read-only) -------------------------------------------------
- apiGroups: [""]
  resources: ["namespaces", "nodes", "serviceaccounts", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  verbs: ["get", "list", "watch"]
# ---- Scanning (container exec) — OMIT this rule for a discovery-only cred ---
# BOTH verbs are required: the container-exec WebSocket upgrade is a GET (→ `get`),
# the legacy SPDY transport is a POST (→ `create`). `create` alone yields
# `cannot get resource "pods/exec"` 403s on the WebSocket path.
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["get", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prooflayer-scanner
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prooflayer-scanner
subjects:
- kind: ServiceAccount
  name: prooflayer-scanner
  namespace: prooflayer-system
---
# Long-lived token Secret tied to the SA. K8s ≥1.24 no longer mints
# tokens automatically; this annotation tells kube-controller-manager
# to populate the Secret's `token` field.
apiVersion: v1
kind: Secret
metadata:
  name: prooflayer-scanner-token
  namespace: prooflayer-system
  annotations:
    kubernetes.io/service-account.name: prooflayer-scanner
type: kubernetes.io/service-account-token
YAML
```

For the **two-tier (recommended) split**, create a second SA without
the `pods/exec` rule for discovery, and reserve the SA above (with the
exec rule) for scanning — store each as its own `kube_config` cred.

For **namespace-scoped scanning** (tighter than cluster-wide exec),
bind the exec rule via a namespaced `Role` + `RoleBinding` in just the
namespaces you scan, rather than a `ClusterRole`. The discovery rules
generally stay cluster-wide (nodes + cluster-scoped RBAC are
cluster-scoped resources).

Extract the three values Prooflayer needs:

```bash
TOKEN=$(kubectl get secret prooflayer-scanner-token -n prooflayer-system \
  -o jsonpath='{.data.token}' | base64 -d)

CA_PEM=$(kubectl get secret prooflayer-scanner-token -n prooflayer-system \
  -o jsonpath='{.data.ca\.crt}' | base64 -d)

SERVER=$(kubectl config view --raw \
  -o jsonpath='{.clusters[?(@.name=="'$(kubectl config current-context)'")].cluster.server}')

echo "Server:   $SERVER"
echo "Token:    ${TOKEN:0:30}..."
echo "CA bytes: ${#CA_PEM}"
```

Verify the scan-tier permission landed (this is the exact check that
catches the `create`-only mistake):

```bash
kubectl auth can-i get pods/exec \
  --as=system:serviceaccount:prooflayer-system:prooflayer-scanner
# must print: yes
```

Verify the identity can list one of the resources discovery walks:

```bash
curl -sk --cacert <(printf '%s' "$CA_PEM") \
  -H "Authorization: Bearer $TOKEN" \
  "$SERVER/api/v1/namespaces" | jq '.items | length'
```

Should print the namespace count without error.

## Alternative: client certificate (kubeadm / kind clusters)

For self-managed clusters using mTLS:

1. Issue or extract a client cert + key for a user that already has
   the appropriate `cluster-reader`-style binding.
2. Read them as PEMs — don't base64-decode.
3. Use the **Build from parts** mode in the Prooflayer UI and choose
   "Client certificate" as the auth method.

`kind`-bootstrapped clusters already contain admin client certs in
their kubeconfig; the **Paste kubeconfig** mode extracts them
automatically via `client-certificate-data` / `client-key-data`.

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (`kind-test (read-only)`, `prod-us-east-1`, etc.)
2. **Kind**: Kubernetes (kubeconfig)
3. Pick a mode:
   - **Paste kubeconfig**: dump a complete kubeconfig YAML into the
     textarea. If the YAML defines multiple contexts, type the chosen
     one into the **Context** field (blank = `current-context`). Click
     **Parse & populate** — the server parses and switches you to the
     Parts view for review.
   - **Build from parts**: type the **Cluster name**, paste the
     **Apiserver URL**, paste the **CA bundle** PEM, pick the auth
     method, and either paste the **Bearer token** or paste both
     **Client certificate** + **Client key** PEMs.
4. **Metadata**: optional `notes` row
5. Save

Prooflayer rejects kubeconfigs that use exec auth providers
(`kubelogin`, `aws-iam-authenticator`) or that reference certs/keys
by file path. The error message points back at this doc.

## Used by

- **Local Kubernetes discovery** (discovery tier) — Phase 1 inventory
  sweep (cluster, namespaces, nodes, workloads, containers, RBAC). Needs
  only the read-only `get/list/watch` rules.
- **Container-exec channel** (scan tier) — execs CTN commands inside a
  container via the apiserver `exec` subresource, making a container a
  first-class scan target. Needs the `get/create pods/exec` rule on top
  of discovery. Resolves the target workload to a live pod, opens a
  WebSocket exec stream over TLS, runs the command.
- **Future**: AKS and EKS do *not* use this credential type directly —
  they take an `azure_spn` / `aws_access_key` and mint an ephemeral bearer
  per sweep/scan. No `kube_config` row for those flavors.

At runtime there's no YAML: Prooflayer renders the credential's parts
(server URL, CA bundle, auth kind, bearer/cert) straight into the scan
environment for both the discovery query and the container-exec channel.

## Rotation

ServiceAccount tokens minted via a `Secret` with the
`service-account-token` type do **not** auto-expire. Rotation triggers:

- Annual hygiene
- Suspected token compromise
- ClusterRoleBinding scope changes (e.g., added a new resource that
  needs explicit grant)

Rotation flow (token-based):

```bash
# Mint a fresh Secret alongside the existing one to avoid downtime
kubectl create secret generic prooflayer-scanner-token-v2 \
  -n prooflayer-system \
  --from-literal=type=kubernetes.io/service-account-token \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - \
    kubernetes.io/service-account.name=prooflayer-scanner -o yaml | \
  kubectl apply -f -

# Extract and rotate the cred in Prooflayer
NEW_TOKEN=$(kubectl get secret prooflayer-scanner-token-v2 \
  -n prooflayer-system -o jsonpath='{.data.token}' | base64 -d)

# Use the Prooflayer UI "Rotate" action on the credential, paste the new
# token, save. Run a fresh discovery (+ scan, if exec-tier) to confirm.

# Delete the old Secret only after the rotated cred is verified working
kubectl delete secret prooflayer-scanner-token -n prooflayer-system
```

Rotation flow (client cert): issue a new cert + key, paste both into
the Rotate flow, then revoke the old cert in your CA.

## Failure modes

| Symptom (server log)                                            | Likely cause                                                                |
|---                                                              |---                                                                          |
| `apiserver 401 Unauthorized`                                    | Token wrong, expired, or pointed at the wrong cluster                       |
| `apiserver 403 Forbidden: cannot list <resource>`               | RBAC too narrow — bind the SA to the full `prooflayer-scanner` ClusterRole above |
| `Connection refused` / `i/o timeout`                            | Apiserver port not reachable from the Prooflayer VM; check firewall + LB    |
| `invalid CA PEM`                                                | `ca_bundle_pem` is not valid PEM (e.g., base64-decoded twice)               |
| `tls: certificate signed by unknown authority`                   | CA bundle doesn't match the apiserver's cert chain — re-extract from cluster |
| `apiserver 200 ... but rows=0` for nodes / RBAC                 | Service account lacks cluster-scoped read on those resources — see above   |
| Server log mentions exec auth                                   | Kubeconfig pasted with `kubelogin` or `aws-iam-authenticator` — mint a static token first |
| **Scan**: `ws handshake: HTTP error: 403 Forbidden`            | SA lacks exec permission. Check `kubectl auth can-i get pods/exec --as=…` |
| **Scan**: `cannot get resource "pods/exec"`                    | SA has `create pods/exec` but not `get` — WebSocket exec needs **both**. Add `get` |
| **Scan**: `no Running pod matched selector … in ns …`           | Workload has no Ready pod (scaled to 0, crash-looping, or selector drift)   |
| **Scan**: `exec stream closed with no status and no output`     | Container has no shell / `env` (scratch / distroless) — can't be exec-scanned |

## Security notes

- The payload contains an effectively long-lived authentication token
  (or a private key). Treat the credential row as equivalent to
  on-disk kubeconfig material at rest.
- The default Prooflayer RBAC (admin-only cred create/rotate/delete)
  applies.
- The discovery-tier ClusterRole grants `get/list/watch` on
  inventory-relevant resources but **not** on Secrets, ConfigMap
  contents, Lease objects, or any namespace-scoped writes. Phase 2
  discovery (Secrets/ConfigMaps metadata only) will require widening;
  Phase 1 does not.
- **`pods/exec` is the most sensitive grant at the Kubernetes RBAC
  layer** — in raw terms it permits running arbitrary commands in any
  pod in scope. **Prooflayer's contract-based execution model bounds
  the effective capability far below that.** Commands are not free-form:
  every command originates from a compiled CTN contract, and Prooflayer
  enforces a per-CTN command allowlist *before* the command reaches the
  container-exec channel. The only commands that exist are read-only
  collection primitives (`cat`, `stat`, `ss`, package-query tools, …).
  There is no platform path from a scan to an arbitrary or mutating
  command — the blast radius is the compiled, read-only CTN suite, not
  "anything `kubectl exec` could do."
- That mitigation covers the **in-platform** threat model. For the
  **token-exfiltration** model (a leaked SA token used outside
  Prooflayer), the raw RBAC still applies — so the at-rest protections
  still matter: the token sits in a role-scoped store (plaintext at rest
  on an encrypted disk), and for CMMC/FedRAMP the grant should be scoped
  as tightly as the cluster allows.
  Prefer namespace-scoped `Role` bindings over a cluster-wide grant
  when only specific namespaces are scanned, and prefer the two-tier
  split (read-only discovery cred + separate exec-capable scan cred) so
  the continuous-inventory identity is provably incapable of code
  execution. The SSP narrative writes itself: *"the scanner holds
  `pods/exec` but can only execute the whitelisted, read-only commands
  defined by its compiled CTN contracts; arbitrary command execution is
  not reachable through the platform."*
- `insecure_skip_tls_verify` is an opt-in checkbox in the Parts view
  — never silently inferred. Avoid it outside development clusters.
- Multi-context kubeconfigs are flattened to a single (cluster, user)
  pair at credential-creation time. The `~/.kube/config` aggregation
  pattern doesn't leak into the stored credential.
