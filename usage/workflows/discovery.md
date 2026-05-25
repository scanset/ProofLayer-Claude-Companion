# Workflow 2 — Discover Assets

Discovery turns **one credential into a list of assets** in the inventory — the
time-to-value step. Instead of hand-entering targets, you point a provider at a
credential and Prooflayer enumerates everything that credential can see, persists
each as an asset, and returns a **signed, transparency-logged envelope** for the
discovery run itself (so "on date D, credential C enumerated X, Y, Z" is itself
evidence).

> Where: the **Discover** page. Concept: [../../components/discovery.md](../../components/discovery.md).
> Each provider runs an inline check (CTN) under the hood; the result is real
> evidence, not a guess.

---

## The basic flow

1. Open **Discover**.
2. Pick the **provider card** for what you want to enumerate.
3. Select the **credential** (the dropdown is filtered to the kind that provider
   needs; it auto-picks the first match).
4. Provide any extra input the card asks for (a cluster id, a CIDR — most need
   only the credential).
5. **Run.** When it completes you get a **Discovered / Created / Updated /
   Skipped** count, a table of the persisted assets, and an expandable view of
   the signed envelope.
6. Repeat for other providers, then move on to
   [auto-link](auto-link-and-assignment.md).

Discovery is **idempotent** — re-running updates existing assets (matched on
provider id) rather than duplicating them.

---

## The providers

| Provider | Credential kind | Enumerates |
|---|---|---|
| **Azure (Resource Graph)** | `azure_spn` | ARM resources the SPN can see — subscriptions, resource groups, VMs, storage, NSGs, VNets, Key Vault, SQL, App Service… |
| **AWS (Resource Explorer)** | `aws_role` / `aws_access_key` | EC2, RDS, S3, Lambda, IAM, and ~20 service categories across the account |
| **Microsoft 365 — Graph** | `azure_spn` | Entra users/groups/devices, Intune, SharePoint, Teams (app-only) |
| **Microsoft 365 — Purview** | `m365_delegated_refresh` | Exchange-backed compliance: retention labels, DLP, audit, eDiscovery (user-context) |
| **Microsoft 365 — PowerShell** | `azure_spn_cert` | PowerShell-only surfaces: DLP detail, mailbox audit, retention policies |
| **Kubernetes (local)** | `kube_config` | cluster identity, namespaces, nodes, workloads, containers, full RBAC |
| **AKS (cluster internals)** | `azure_spn` + cluster | the AKS cluster's K8s internals; Prooflayer mints the apiserver token (no kubeconfig) |
| **EKS (cluster internals)** | aws cred + cluster | the EKS cluster's K8s internals; Prooflayer assumes the role + mints a presigned token |
| **GitHub (orgs + repos)** | `github_pat` | every org the PAT sees + the user's repos, each as an SDLC repository asset |
| **This host (local)** | *(none)* | registers the Prooflayer host itself (OS, hostname, basic service probe) |
| **Subnet sweep** | `network_target` | live hosts in a CIDR via TCP connect probe — see [../../components/network-sweep-discovery.md](../../components/network-sweep-discovery.md) |

(A few providers — CSV/YAML import, GCP, Okta, Google Workspace, DHCP, EDR
re-read — appear as **staged/disabled** cards in the alpha.)

### Two conveniences worth knowing

- **AKS/EKS cluster pickers auto-populate.** After you run Azure or AWS
  discovery, the AKS/EKS cards offer a dropdown of clusters already in inventory
  (you can also paste an ARM id / cluster ARN). Run the cloud discovery first.
- **Cross-cloud bridging.** K8s and network-sweep discovery link the assets they
  find back to the cloud resources that share an identity (a node's providerID, a
  shared IP), so the asset graph stays connected across providers.

---

## What you get, and what's next

Each discovered asset lands in the inventory with its type, provider, metadata,
and graph edges (`parents`/`children`) — ready to have policies bound to it.
Discovery **does not** scan for compliance; it builds the inventory. The next
step is binding policies:

→ [auto-link-and-assignment.md](auto-link-and-assignment.md)

> Deliberate, not magic: discovery only runs when you click it, and the CIDR /
> OS profile / cluster are operator-supplied — no silent auto-detection. (See the
> "signals, not triggers" note in [../../components/discovery.md](../../components/discovery.md).)
