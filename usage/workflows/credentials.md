# Workflow 1 — Set Up Credentials

A **credential** is the secret material Prooflayer authenticates as when it
discovers or scans. It's step 1 because nothing else (discovery, scanning a
remote target) works without one — except local-channel scans of the container
host itself, which need no credential.

> Where: **Admin → Credentials**. Per-kind field/privilege/how-to-obtain
> reference: [../credentials/](../credentials/README.md). Concept (credential vs
> asset vs binding): [../../components/inventory.md](../../components/inventory.md).

---

## The basic flow

1. Open **Admin → Credentials**.
2. Click **Add credential**.
3. Enter a **Name** (e.g. `prod-azure-reader`).
4. Pick a **Kind** from the dropdown (the 12 kinds below).
5. Fill the kind-specific **payload** fields.
6. *(Optional)* add **metadata** rows — non-secret context (region, subscription
   id, tenant display name) that's safe to show in listings.
7. *(Optional)* set an **expiry** date so the UI can warn before it lapses.
8. **Save.** The credential appears in the list; the payload is stored
   role-scoped (plaintext JSONB, secured by host disk encryption + DB role
   scoping — not app-layer encryption; see [../credentials/](../credentials/README.md)).

**Rotate** (replace the secret, keep the name/identity) and **Delete** are
per-row actions. Every create/rotate/delete is admin-gated.

---

## The 12 kinds (what the dropdown offers)

| Kind | Authenticates as | Per-kind detail |
|---|---|---|
| `aws_access_key` | AWS IAM user (static key) | [../credentials/aws_access_key.md](../credentials/aws_access_key.md) |
| `aws_role` | AWS IAM role (assume) | [../credentials/aws_role.md](../credentials/aws_role.md) |
| `azure_spn` | Entra app reg (client secret) | [../credentials/azure_spn.md](../credentials/azure_spn.md) |
| `azure_spn_cert` | Entra app reg (cert) | [../credentials/azure_spn_cert.md](../credentials/azure_spn_cert.md) |
| `m365_delegated_refresh` | a user delegating to a public-client app | [../credentials/m365_delegated_refresh.md](../credentials/m365_delegated_refresh.md) |
| `gcp_sa_key` | GCP service account (JSON key) | [../credentials/gcp_sa_key.md](../credentials/gcp_sa_key.md) |
| `ssh_key` | a Unix login over SSH | [../credentials/ssh_key.md](../credentials/ssh_key.md) |
| `winrm_password` | a Windows login over WinRM | [../credentials/winrm_password.md](../credentials/winrm_password.md) |
| `github_pat` | a GitHub user (fine-grained PAT) | [../credentials/github_pat.md](../credentials/github_pat.md) |
| `kube_config` | a Kubernetes apiserver identity | [../credentials/kube_config.md](../credentials/kube_config.md) |
| `network_target` | *(no secret)* a CIDR to sweep | [../credentials/network_target.md](../credentials/network_target.md) |
| `local` | *(no secret)* the Prooflayer host itself | [../credentials/local.md](../credentials/local.md) — system-managed; you don't create it manually |

---

## Three kinds have a non-standard flow

A few credentials aren't a simple "paste a secret":

- **`m365_delegated_refresh` — device-code modal.** On save, Prooflayer starts
  Microsoft's device-code sign-in and shows a **one-time code + verification
  URL**. You open the URL, sign in (as a Compliance/Global admin), and the
  refresh token is captured and stored. Prooflayer then rotates it automatically
  on each discovery sweep. (Use the *delegated* app registration's client id —
  the app-only SPN's client id fails here.)
- **`kube_config` — paste-and-parse vs build-from-parts.** Either paste a full
  kubeconfig and click **Parse & populate** (Prooflayer extracts the cluster
  URL, CA, and auth, and rejects exec-auth providers like `kubelogin`), or fill
  the cluster URL / CA / token-or-cert fields directly.
- **`github_pat` — Test button.** After saving, **Test** confirms the token by
  showing the login, accessible orgs, and email — so you catch a bad/expired
  token before discovery.

---

## Picking the right scope

Give each credential the **least privilege** its job needs — read-only wherever
possible (a `Reader`-scoped SPN, a read-only IAM policy, a view-only K8s
ClusterRole, a fine-grained read PAT). The credential determines what discovery
can enumerate and what a scan can read; nothing more is needed, and a read-only
identity keeps the scanner's blast radius minimal. The
[test_fixtures/credentials/](../../test_fixtures/credentials/README.md) docs
describe minimal-privilege identities to mint for evaluation.

Next: [discovery.md](discovery.md) — turn a credential into assets.
