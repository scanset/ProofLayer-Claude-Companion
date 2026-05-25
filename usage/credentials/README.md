# Credentials

Operator-facing reference for every credential type Prooflayer accepts.
Each credential identifies a secret-bearing principal Prooflayer
authenticates as when running discovery or evidence-collection scans.

> Part of the Prooflayer guide. This is **step 1 of the core loop** in
> [../README.md](../README.md) (add credential → discover → link → scan), and
> the admin-side governance of credentials is in
> [admin/ §3](../../admin/README.md#3-credential-governance-apiinventorycredentials).
> The concept (credential vs asset vs binding) is
> [components/inventory.md](../../components/inventory.md).

The credential **payload** is the secret material itself. The credential
**metadata** is the non-secret operational context (subscription_id, tenant
display name, region, etc.) — safe to surface in the UI and logs.

> **Storage model (read this).** The payload is **secret but not app-layer
> encrypted** — it is held as plaintext at rest under scoped, least-privilege
> access. Confidentiality comes from: host disk encryption, least-privilege
> access scoping (the write path that stores a credential is separate from the
> read-only path that reads it, and only on scan dispatch), loopback-only
> reachability, and audit logging — **not** from an encrypting "vault." This is
> a deliberate, documented decision; column-level encryption can be added later
> if a 3PAO requires it. Where this guide or a per-kind page says "credential
> store," that means this least-privilege-scoped store, not an encryptor.

## Index

| Kind                       | Identity it represents                              | Auth flow                              | Doc |
|---                         |---                                                  |---                                     |---|
| `aws_access_key`           | AWS IAM user                                         | static access-key signing               | [aws_access_key.md](aws_access_key.md) |
| `aws_role`                 | AWS IAM role assumed from a source identity         | STS AssumeRole                          | [aws_role.md](aws_role.md) |
| `azure_spn`                | Entra ID app registration (client-secret)           | OAuth2 `client_credentials`             | [azure_spn.md](azure_spn.md) |
| `azure_spn_cert`           | Entra ID app registration (cert-bound)               | OAuth2 JWT-assertion (cert-signed)       | [azure_spn_cert.md](azure_spn_cert.md) |
| `m365_delegated_refresh`   | Entra ID user delegating to a public-client app reg | OAuth2 `refresh_token`                   | [m365_delegated_refresh.md](m365_delegated_refresh.md) |
| `gcp_sa_key`               | GCP service account (JSON key)                       | Google JWT-assertion                     | [gcp_sa_key.md](gcp_sa_key.md) |
| `ssh_key`                  | Unix user via OpenSSH key auth                       | SSH publickey                            | [ssh_key.md](ssh_key.md) |
| `winrm_password`           | Windows user via WinRM HTTP(S)                       | basic/NTLM/Kerberos over WinRM           | [winrm_password.md](winrm_password.md) |
| `github_pat`               | GitHub user via fine-grained PAT                     | bearer over the GitHub REST API          | [github_pat.md](github_pat.md) |
| `kube_config`              | Kubernetes apiserver identity (SA token or mTLS)     | bearer or client cert against `kube-apiserver` | [kube_config.md](kube_config.md) |
| `local`                    | The Prooflayer host itself (no secret)               | in-process (no auth)                     | [local.md](local.md) |
| `network_target`           | A CIDR to sweep (no secret — a scan-target spec)     | none (TCP probe)                          | [network_target.md](network_target.md) |

## Adding credentials

System-UI → **Admin** → **Credentials** → **Add credential**. Pick a
kind from the dropdown, fill in the payload fields, paste any
non-secret operational metadata (one row per key/value), click Save.

Rotation is via the **Rotate** action on each credential card. Rotation always
creates a new audit-log entry — credentials are append-only from the
transparency perspective even though the payload is overwritten in place.

## Which credential drives which discovery

| Credential kind            | Drives                                                                                              |
|---                         |---                                                                                                  |
| `aws_access_key`, `aws_role` | AWS Resource Explorer discovery (Phase 2)                                                          |
| `azure_spn`                | Azure Resource Graph (ARM) + most Microsoft Graph paths (Entra, Intune, MIP, SharePoint, Teams)     |
| `azure_spn_cert`           | PowerShell-only Microsoft surfaces via cert-auth `Connect-IPPSSession` (DLP, mailbox audit, etc.)  |
| `m365_delegated_refresh`   | Exchange-backed Microsoft Graph endpoints gated to user-context auth (retention labels, eDiscovery) |
| `gcp_sa_key`               | GCP discovery (future phase, not yet built)                                                          |
| `ssh_key`                  | Linux host scans via the SSH channel                                                                 |
| `winrm_password`           | Windows host scans via the WinRM channel                                                             |
| `github_pat`               | GitHub orgs + repos discovery + every `github_*` CTN                                                 |
| `kube_config`              | Kubernetes (local-flavor) discovery against any reachable apiserver; the container-exec scan channel |
| `local`                    | The Prooflayer host as an asset; in-process scans of the Prooflayer VM itself                        |
| `network_target`           | Network discovery (`discover/network`) — TCP sweep of a CIDR → a CIDR-range asset + a per-host asset |

For Microsoft, three credentials cover the surface together because no
single auth flow reaches every endpoint — see the credential-specific
docs for the rationale.

## Rotation cadence guidance

| Kind                       | How material expires                                              | Recommended rotation                                |
|---                         |---                                                                |---                                                  |
| `aws_access_key`           | No automatic expiry                                                | Quarterly, or whenever IAM policy changes            |
| `aws_role`                 | Per-session via STS (auto-rotated by SDK)                          | Just rotate the source identity / external_id       |
| `azure_spn`                | Client secret expires per `secret_validity_months` (default 12mo) | On terraform-driven secret rotation                 |
| `azure_spn_cert`           | Cert expires per `pwsh_cert_validity_hours` (default 1yr)         | Bump TF validity → `terraform apply` → re-paste     |
| `m365_delegated_refresh`   | Refresh token: ~90 days idle, otherwise indefinitely self-extending| Re-bootstrap if/when refresh chain dies              |
| `gcp_sa_key`               | No automatic expiry                                                | Quarterly                                            |
| `ssh_key`                  | No automatic expiry                                                | On role change or yearly                            |
| `winrm_password`           | Per AD password policy                                             | Per AD password policy                              |
| `github_pat`               | Fine-grained PATs: max 1yr; classic: optional                      | Per `metadata.expires_at`, or 90d default            |
| `kube_config`              | SA tokens: none. Client certs: per CA validity                     | Yearly hygiene, or on RBAC scope change             |
| `local`                    | N/A — no secret                                                    | N/A                                                  |
| `network_target`           | N/A — no secret (a scan-target spec)                               | N/A — edit the CIDR when the range changes           |

## Security model

- Payload is role-scoped **plaintext at rest** (no app-layer encryption) — see
  the Storage model note above; confidentiality is host disk encryption +
  least-privilege access scoping + loopback-only reachability + audit logging.
- All write operations (create, rotate, delete) are gated to the super-admin role.
- Reads return a credential summary (no payload field) by default; the payload
  is only fetched on the scan-dispatch path for in-process use.
- Every credential operation produces a transparency-log entry.
