# `m365_delegated_refresh`

Delegated (user-context) Microsoft Graph credential. Auths as a real
human user against Entra ID using a long-lived refresh token, bootstrapped
via the OAuth2 device-code flow.

## What it represents

A specific human's permission set — captured once via interactive
sign-in, then reused unattended via refresh-token rotation. The
underlying app registration is a public client (`prooflayer-scanner-delegated`);
the user signs in to it once, consents to the requested delegated
scopes, and Microsoft issues a refresh token. Subsequent scans exchange
the refresh token for short-lived access tokens with the user's
permissions.

Why this exists alongside `azure_spn`: Microsoft gates a chunk of the
M365 Graph surface to **user-context auth only** on Business Premium /
Purview Suite for BP tier. Specifically, Exchange-backed compliance
endpoints (`/security/labels/retentionLabels`, `/security/cases/ediscoveryCases`,
`/security/auditLog/queries`) do a secondary RBAC check against the
principal in the EXO compliance role evaluator — and that evaluator
silently refuses SPN principals on lower tiers even when Graph
permissions are correctly consented. A real user authenticating with
their existing compliance admin role bypasses this gate.

## Payload fields

| Field           | Required | Description                                                                |
|---              |---       |---                                                                         |
| `tenant_id`     | yes      | Entra tenant ID                                                             |
| `client_id`     | yes      | Public-client app registration's Application ID (the *delegated* SPN)        |
| `refresh_token` | yes      | Long-lived refresh token. Empty at create time, filled in by the bootstrap flow. **Rotates on every use.** |

## Metadata fields (non-secret, operator-set)

| Key                    | Purpose                                                                |
|---                     |---                                                                     |
| `tenant_display_name`  | Human label for the tenant                                              |
| `enrolled_upn`         | The user who completed the device-code bootstrap                        |
| `enrolled_at`          | When the device-code flow completed                                     |

## How to provision the underlying app registration

your delegated-app Terraform
creates the public-client app reg:

```bash
cd <your SPN terraform>
terraform apply
terraform output -raw delegated_client_id  # → Client ID
terraform output -raw tenant_id            # → Tenant ID
```

The terraform provisions:
- App registration `prooflayer-scanner-delegated`
- `public_client.redirect_uris = ["https://login.microsoftonline.com/common/oauth2/nativeclient"]`
- `fallback_public_client_enabled = true` (REQUIRED for device-code flow)
- Delegated scopes consented tenant-wide: `offline_access`, `User.Read`,
  `RecordsManagement.Read.All`, `eDiscovery.Read.All`, `AuditLogsQuery.Read.All`

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (e.g. `m365-delegated`)
2. **Kind**: M365 Delegated (refresh token)
3. **Tenant ID**: paste `terraform output -raw tenant_id`
4. **Client ID**: paste `terraform output -raw delegated_client_id`
   (NOT the app-only `client_id` — they look identical but the
   delegated one is the *public client*)
5. Click **Save** — this opens the **device-code bootstrap modal**

In the modal:
1. Modal shows a one-time code (e.g. `ABC-123-XYZ`) + the URL
   `https://microsoft.com/devicelogin`
2. **Open the URL on any browser** (your laptop, phone, etc. — does not
   need to be on the Prooflayer VM)
3. Enter the code, sign in as a user with compliance read perms
   (Global Admin / Compliance Administrator / Records Management role)
4. Consent to the requested scopes
5. Prooflayer's server polls Microsoft's token endpoint in the
   background; modal flips to "Enrolled successfully" within ~5 sec
6. Click Done

After enrollment, the credential's payload has a non-empty `refresh_token`.

## Used by

**Purview (Exchange-backed Graph) discovery** —
discovers the Exchange-backed Microsoft Graph beta surface:

| Endpoint                                        | Asset type                |
|---                                              |---                        |
| `/beta/security/labels/retentionLabels`         | `M365::RetentionLabel`    |
| `/beta/security/triggerTypes/retentionEventTypes` | `M365::RetentionEventType`|
| `/beta/security/triggers/retentionEvents`       | `M365::RetentionEvent`    |
| `/v1.0/security/cases/ediscoveryCases`          | `M365::EdiscoveryCase`    |
| `/beta/security/auditLog/queries`               | `M365::AuditLogQuery`     |

## Rotation

**Refresh tokens auto-rotate on every use** — same lifecycle as an
app secret. After each discovery sweep:

1. The collector exchanges the current refresh_token for a fresh access_token
2. Microsoft issues a new refresh_token in the response (since
   `offline_access` scope is requested)
3. Prooflayer persists the new refresh_token in place of the old one
4. The next sweep uses the new refresh_token

As long as discovery runs at least once every ~90 days, the chain
extends indefinitely.

**Re-bootstrap is only needed when:**
- The chain breaks (90 days idle, user revokes consent, tenant
  Conditional Access policy change invalidates the token, admin
  manually revokes the user's session)
- The credential's `refresh_token` field becomes empty (it was wiped
  by a failed rotation or never bootstrapped)

To re-bootstrap: delete the credential, re-create it (the form will
re-fire the device-code flow on Save).

## Failure modes

| Symptom                                                  | Likely cause                                                                                       |
|---                                                       |---                                                                                                 |
| Bootstrap modal hangs on `polling`, then `expired`        | Operator didn't complete browser sign-in within ~15 min                                             |
| `AADSTS7000218` on poll                                  | App registration is missing `fallback_public_client_enabled = true`. Verify with `az ad app show`   |
| `AADSTS700016: Application not found`                    | `client_id` and `tenant_id` swapped in the form. Verify with `terraform output`                     |
| `invalid_grant` on subsequent discovery sweeps           | Refresh token chain expired or was revoked. Re-bootstrap                                            |
| Discovery starts but returns `403 Forbidden` on retention labels | User who bootstrapped doesn't have the Compliance Administrator role                                |

## Security notes

- Refresh token is held as role-scoped plaintext at rest (no app-layer encryption). Never logged.
- Refresh tokens are bound to the consenting user — revoking the
  user (or their MFA) invalidates the chain. This is *desired* security
  behavior, not a bug.
- The user whose context the refresh token represents matters for
  audit: every discovered asset's `metadata.observations` carries
  the credential's ID, which links back through `enrolled_upn` to a
  specific human's compliance role. Auditors can trace which user's
  delegation discovered what.
- Conditional Access can kill the chain. If your tenant has CA policies
  that re-evaluate periodically, the next refresh exchange may force a
  re-bootstrap.
