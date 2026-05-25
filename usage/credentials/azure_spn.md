# `azure_spn`

Entra ID app registration with a client secret. The default AWS-equivalent
for the Microsoft side — app-only auth via OAuth2 `client_credentials`
flow against Entra ID, returning tokens for whatever resource audience
the app's API permissions grant.

## What it represents

A non-human identity (app registration's service principal) in your
Entra tenant, with admin-consented API permissions on Microsoft Graph
and/or Azure Resource Manager. Authenticates by presenting the client
secret to AAD's token endpoint.

## Payload fields

| Field           | Required | Description                                           |
|---              |---       |---                                                    |
| `client_id`     | yes      | App registration's Application (client) ID            |
| `tenant_id`     | yes      | Entra tenant ID                                       |
| `client_secret` | yes      | App registration's secret (secret)         |

## Metadata fields (non-secret, operator-set)

| Key                    | Purpose                                                                       |
|---                     |---                                                                            |
| `subscription_id`      | Default Azure subscription for ARM calls (used by `az login`-style preflight) |
| `tenant_display_name`  | Human label for the tenant (e.g. `Scanset Production`)                        |

## How to provision

Provision it with Terraform — see the credential fixtures ([test_fixtures/credentials/](../../test_fixtures/credentials/README.md)):

```bash
cd <your SPN terraform>
terraform apply
# Outputs:
#   client_id          ← paste into Prooflayer
#   tenant_id          ← paste into Prooflayer
#   client_secret      ← paste into Prooflayer (sensitive)
#   subscription_id    ← set as `subscription_id` metadata key
```

The terraform provisions:
- App registration `prooflayer-scanner`
- Service principal in the tenant
- A rotating client secret (TTL per `var.secret_validity_months`,
  default 12 months)
- Reader role assignment at the subscription scope
- Admin-consented Graph application permissions (see variables.tf
  `graph_application_permissions` for the current set)

For manual provisioning (one-tenant scenarios without terraform), follow your
organization's Entra app-registration runbook: create the app, add a client
secret, then grant and admin-consent the application permissions listed above.

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (e.g. `scanset-prod`)
2. **Kind**: Azure SPN
3. **Client ID**: paste the `client_id` terraform output
4. **Tenant ID**: paste the `tenant_id` terraform output
5. **Client secret**: paste via `terraform output -raw client_secret`
6. **Metadata**: set `subscription_id` and `tenant_display_name`

## Used by

- **Azure Resource Graph (ARM) discovery** —
  Token audience: `https://management.azure.com`
- **Microsoft Graph discovery (app-only paths)** —
  Token audience: `https://graph.microsoft.com`. Reaches ~75% of M365
  surface: Entra users/groups/devices, Intune, MIP sensitivity labels,
  SharePoint sites, Teams, CA policies, role assignments, etc.

What it does NOT reach:
- Exchange-backed compliance surfaces gated to user-context auth
  (retention labels, eDiscovery, audit log search) — see
  [`m365_delegated_refresh`](m365_delegated_refresh.md)
- PowerShell-only Microsoft surfaces (DLP policies, mailbox audit
  config, admin audit log config) — see
  [`azure_spn_cert`](azure_spn_cert.md)
- **AKS cluster internals + container scanning** — same SPN, but
  needs additional roles on both the Azure and Kubernetes sides; see
  next section.

## AKS — cluster discovery + container scanning

The same `azure_spn` doubles as the Kubernetes credential for
AKS — no separate `kube_config` needed. Prooflayer mints the
apiserver connection in-process so there's no stored kubeconfig and no
`kubelogin` exec provider. Used by both AKS internals discovery and
container scanning.

The token exchange works by:

1. ARM token (`https://management.azure.com/.default`).
2. `POST <cluster-resource-id>/listClusterUserCredential` (**singular** —
   the plural spelling 404s) → kubeconfig; Prooflayer keeps only the
   apiserver `server` FQDN + `certificate-authority-data`, discards the
   exec stanza.
3. AKS AAD server-app token
   (`6dae42f8-4368-4678-94ff-3960e28e3630/.default`) — this *is* the
   apiserver bearer, exactly what `kubelogin --login spn` would mint.

### Required permissions

**Azure RBAC (control plane)** — assigned at the cluster scope, see
your AKS Terraform:

| Role | Grants | Why |
|---   |---     |---  |
| `Reader` (subscription) | enumerate `Microsoft.ContainerService/managedClusters` | discovery sees the cluster shells at all (already required above) |
| `Azure Kubernetes Service Cluster User Role` | `…/managedClusters/listClusterUserCredential/action` | fetch apiserver FQDN + CA bundle (step 2) |

`Cluster User Role` does **not** grant any in-cluster authority — it
only returns the connection material. Authorization to read resources
or exec into pods is the Kubernetes RBAC layer below.

**Kubernetes RBAC (data plane)** — in-cluster `ClusterRole` +
`ClusterRoleBinding`, see your AKS RBAC Terraform.
The cluster must have managed AAD integration enabled. With
`azure_rbac_enabled = false`, in-cluster bindings handle authz; the
binding subject is the SPN's **objectId as `kind: User`** (the apiserver
maps the token's `oid` claim to the username — a mismatch here is a 403
at the authz step, not authn):

| Tier | Resources | Verbs |
|---   |---        |---    |
| Discovery | `namespaces`, `nodes`, `serviceaccounts`, `pods`; `apps/{deployments,statefulsets,daemonsets}`; `batch/{jobs,cronjobs}`; `rbac/{roles,rolebindings,clusterroles,clusterrolebindings}` | `get`, `list`, `watch` |
| Scan (container exec) | `pods/exec` | `get`, `create` |

Both `get` **and** `create` on `pods/exec` are required:
WebSocket exec (Prooflayer's container-exec channel) authorizes as `get`;
SPDY exec authorizes as `create`. Granting only one yields a 403 mid-handshake.
Omit the scan tier entirely for a discovery-only binding.

### Adding in Prooflayer

No new credential — reuse the existing `azure_spn`. On the AKS
container asset, assign the `azure_spn` cred + the container-exec channel;
Prooflayer walks the asset graph to the parent cluster, reads its AKS
resource id, and runs the token exchange above. Discovery links the
Kubernetes cluster asset to its AKS managed-cluster asset automatically.

## Rotation

Client secret expires per terraform's `secret_validity_months` variable
(default 12 months). To rotate:

```bash
cd <your SPN terraform>
terraform apply  # generates new secret; old one is invalidated
terraform output -raw client_secret  # paste into Prooflayer's Rotate flow
```

System-UI surfaces "expires in N days" warnings if you set
`Credential.expires_at` at create time matching the terraform validity
window.

## Failure modes

| Symptom                                                                | Likely cause                                                                                |
|---                                                                     |---                                                                                          |
| `AADSTS7000215: Invalid client secret`                                 | Secret wasn't rotated cleanly, or you copy-pasted a stale value                              |
| `AADSTS70011: Invalid scope` on Graph calls                            | App reg is missing the right Application permission, or admin consent wasn't granted         |
| `Authorization_RequestDenied` (Graph 403)                              | Same as above — specific permission not granted                                              |
| `AuthorizationFailed` (ARM 403)                                        | SPN missing Azure RBAC role at the target scope; check the Reader assignment                |
| Discovery succeeds but only sees subset of resources                   | Reader role assigned at narrower scope than expected (resource-group instead of subscription)|
| `listClusterUserCredential` ARM 404                                    | Calling the **plural** `listClusterUserCredentials` — the real action/endpoint is singular  |
| `…not authorized to perform listClusterUserCredential/action` (ARM 403)| SPN missing `Azure Kubernetes Service Cluster User Role` at the cluster scope                |
| AKS apiserver 403 on list/get during discovery                         | SPN objectId not bound (or `kind: User` name ≠ token `oid`) to an in-cluster `ClusterRole`  |
| AKS apiserver 403 mid-exec-handshake during scan                       | `pods/exec` rule missing `get` (WebSocket) or `create` (SPDY) — grant both                  |

## Security notes

- Client secret is held as role-scoped plaintext at rest (no app-layer encryption).
- The same SPN identity is used for both ARM and Graph audiences —
  Microsoft scopes by API permission, not by token audience.
- Prefer narrower built-in roles than `Reader` if the discovery scope
  is well-defined (e.g. `Storage Account Reader` for storage-only
  scanning).
- The `terraform apply` operator needs Cloud Application Administrator
  (or higher) Entra role to grant admin consent on Graph permissions.
  Reader / Contributor alone is not enough — those are Azure RBAC
  roles, not Entra ID roles.
