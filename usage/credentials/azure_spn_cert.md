# `azure_spn_cert`

Entra ID app registration with a certificate keyCredential. The
production-grade alternative to [`azure_spn`](azure_spn.md) (which uses
a client secret) for use cases that require certificate-based JWT
assertion authentication — currently PowerShell against Microsoft's
compliance backend (`Connect-IPPSSession`), where Microsoft does not
accept client_secret auth.

## What it represents

Same Entra identity concept as `azure_spn` — a non-human app
registration's service principal — but with cert auth instead of
shared-secret auth. Auths by signing a JWT assertion with the private
key; Microsoft verifies the signature against the public cert uploaded
as a keyCredential on the app.

This credential type is **capability-neutral**. The specific app
registration determines what APIs are reachable:
- Graph (with Application permissions) — `Microsoft.Graph` PowerShell
  module, Graph cert-auth from raw HTTP
- Exchange Online / IPPSSession — `Connect-ExchangeOnline` /
  `Connect-IPPSSession` with `-AppId -Certificate -Organization`
- ARM cert-auth — Azure SDK supports cert-bound SPNs for ARM too

Prooflayer's current consumer is the PowerShell compliance scanner.
Future Graph or ARM cert-auth scanners would reuse the same credential
payload.

## Payload fields

| Field             | Required | Description                                                          |
|---                |---       |---                                                                   |
| `tenant_id`       | yes      | Entra tenant ID                                                       |
| `client_id`       | yes      | App registration's Application (client) ID — the cert-bound app reg   |
| `certificate_pem` | yes      | PEM-encoded X.509 certificate (the public half — non-secret)          |
| `private_key_pem` | yes      | PEM-encoded RSA private key (secret)                       |

Both PEMs are pasted as multi-line text in the form, same UX as
[`ssh_key`](ssh_key.md).

## Metadata fields (non-secret, operator-set)

| Key                    | Purpose                                                                              |
|---                     |---                                                                                   |
| `organization`         | **Required for the pwsh discoverer.** Tenant primary domain (e.g. `scanset.io`). Passed to `Connect-IPPSSession -Organization`. |
| `tenant_display_name`  | Human label for the tenant                                                            |
| `cert_expires_at`      | ISO-8601 timestamp the cert expires (set at create time for UI countdown reminders)   |

## How to provision

Terraform manages a dedicated cert-based app registration in
your SPN cert-auth Terraform:

```bash
cd <your SPN terraform>
terraform apply

terraform output -raw pwsh_client_id     # → Client ID
terraform output -raw tenant_id          # → Tenant ID
terraform output -raw pwsh_certificate   # → Certificate (PEM)
terraform output -raw pwsh_private_key   # → Private key (PEM, sensitive)
```

The terraform provisions:
- App registration `prooflayer-scanner-pwsh`
- Service principal in the tenant
- `Exchange.ManageAsApp` application permission granted with admin consent
- A terraform-generated self-signed RSA-2048 cert + key
- The cert uploaded as a `keyCredential` on the app registration

After `terraform apply`, one **manual** Exchange-side step is required
to allow PowerShell-side IPPSSession to recognize the SPN:

```powershell
# Connect from a Windows admin workstation as a Global Admin
Connect-IPPSSession

$pwshAppId        = "<terraform output -raw pwsh_client_id>"
$pwshSpnObjectId  = "<terraform output -raw pwsh_service_principal_object_id>"

# 1. Register the SPN as an EXO service principal proxy
New-ServicePrincipal -AppId $pwshAppId `
                     -ObjectId $pwshSpnObjectId `
                     -DisplayName "Prooflayer Scanner - PowerShell"

# 2. Add the SPN to a compliance role group
Add-RoleGroupMember -Identity "ComplianceAdministrator" -Member $pwshSpnObjectId

# Verify
Get-RoleGroupMember -Identity "ComplianceAdministrator" |
    Where-Object { $_.Name -match "prooflayer" }
```

These two cmdlets aren't terraform-manageable (Microsoft hasn't
exposed EXO role-group membership as a Graph-addressable resource).

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (e.g. `spn_cert`)
2. **Kind**: Azure SPN (cert-based)
3. **Tenant ID**: paste `terraform output -raw tenant_id`
4. **Client ID**: paste `terraform output -raw pwsh_client_id`
   (NOT the app-only `client_id` — they look identical but `pwsh_client_id`
   is the one with the cert keyCredential)
5. **Certificate (PEM)**: paste `terraform output -raw pwsh_certificate`
6. **Private key (PEM)**: paste `terraform output -raw pwsh_private_key`
7. **Metadata**: at minimum set `organization` to your tenant primary
   domain (e.g. `scanset.io`). The pwsh discoverer refuses to run
   without this.

## Used by

- **PowerShell (IPPSSession) discovery** —
  cert-auth PowerShell sweep against IPPSSession for DLP policies,
  audit retention policies, retention compliance policies, admin
  audit log config, and any future PowerShell-only compliance surface

The credential is also storage-ready for future Graph cert-auth or
ARM cert-auth scanners — they'd reuse the same payload shape without
any changes to this credential type.

## Rotation

Cert validity is set by terraform's `pwsh_cert_validity_hours` variable
(default 8760 = 1 year). To rotate before expiry:

```bash
cd <your SPN terraform>
# Optionally bump validity:
# terraform apply -var=pwsh_cert_validity_hours=17520  # 2 years
terraform apply  # regenerates cert + key, uploads new cert to SPN
terraform output -raw pwsh_certificate  # → paste into Prooflayer Rotate
terraform output -raw pwsh_private_key  # → paste into Prooflayer Rotate
```

Rotation does NOT require redoing the `New-ServicePrincipal` /
`Add-RoleGroupMember` Exchange-side steps — those are bound to the
app registration's ObjectId, not the cert.

## Failure modes

| Symptom                                                              | Likely cause                                                                    |
|---                                                                   |---                                                                              |
| `AADSTS700016: Application with identifier <X> was not found`         | `client_id` and `tenant_id` were pasted into the wrong fields — both are UUIDs, easy to confuse. Verify with `terraform output` |
| `AADSTS7000218: parameter 'client_assertion' or 'client_secret'`      | App registration is missing `fallback_public_client_enabled = true` (or other Microsoft auth-mode mis-config). Verify via `az ad app show --id <appid> --query isFallbackPublicClient` |
| Discovery refuses to start, citing a missing `organization`           | Operator forgot to set `metadata.organization` on the credential                |
| `Get-DlpCompliancePolicy ... ManagementObjectNotFound` or `Unauthorized` | SPN not registered via `New-ServicePrincipal` or not in `ComplianceAdministrator` |
| Discovery starts but cmdlets fail after ~5 min                       | EXO compliance role-group propagation lag (15-30 min after initial add)         |

## Security notes

- Private key is held as role-scoped plaintext at rest (no app-layer encryption), never logged.
- Cert keyCredential on the SPN expires per the cert's `NotAfter` —
  rotation is required even if the underlying app registration is
  fine.
- Compliance role-group membership is a separate auth gate on top of
  the Graph permission. The SPN can have `Exchange.ManageAsApp` granted
  but still fail IPPSSession auth if it's not in a compliance role
  group.
- Cert-based auth is preferred over client_secret for ANY app-only
  flow because (a) leaked cert is detectable via thumbprint mismatch,
  (b) Microsoft's audit logs distinguish cert auth from secret auth.
