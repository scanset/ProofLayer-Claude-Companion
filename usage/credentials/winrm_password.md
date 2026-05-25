# `winrm_password`

Windows user + password for authenticating via WinRM (Windows Remote
Management). Used for host-mode scans against Windows targets — the
WinRM channel reaches the host over HTTP(S) instead of SSH.

## Status

The WinRM channel exists, but the discoverer + dispatch path that consumes
`winrm_password` credentials at scan time is not yet wired into the active
flow. The credential type accepts and stores payloads correctly; running a scan
against a Windows host today is not yet supported end-to-end.

Documenting now so the auth model is captured; the per-scanner "Used
by" section gets filled in when the Windows host scan path lands.

## What it represents

A Windows user account (local or domain) that can authenticate against
WinRM on the target host. WinRM accepts several auth schemes (Basic,
NTLM, Kerberos, CredSSP); the channel picks based on the target's
configured listener and the credential payload shape.

## Payload fields

| Field      | Required | Description                                                       |
|---         |---       |---                                                                |
| `username` | yes      | Windows user account (local: `WORKGROUP\Administrator`, domain: `CONTOSO\svc-prooflayer` or `svc-prooflayer@contoso.local`) |
| `password` | yes      | Account password (secret)                              |

## Metadata fields (non-secret, operator-set)

| Key      | Purpose                                                              |
|---       |---                                                                   |
| `domain` | Active Directory domain (or `WORKGROUP` / `.` for local accounts)    |
| `notes`  | Free-form context                                                     |

## How to provision

For a domain environment:

```powershell
# As a Domain Admin on a DC or AD-joined admin workstation
New-ADUser -Name "svc-prooflayer" `
           -SamAccountName "svc-prooflayer" `
           -UserPrincipalName "svc-prooflayer@contoso.local" `
           -AccountPassword (Read-Host -AsSecureString "Set password") `
           -Enabled $true `
           -PasswordNeverExpires $false `
           -CannotChangePassword $false

# Grant least-privilege WinRM access via Group Policy:
#   Windows Settings → Security Settings → Restricted Groups
#   Add svc-prooflayer to "Remote Management Users" on target hosts
```

For local accounts (small workgroup):

```powershell
# On each target host
$pwd = ConvertTo-SecureString "StrongPasswordHere" -AsPlainText -Force
New-LocalUser -Name "prooflayer" -Password $pwd -PasswordNeverExpires
Add-LocalGroupMember -Group "Remote Management Users" -Member "prooflayer"
```

Verify WinRM is listening + the user can connect:

```powershell
# From a host that can reach the target
Test-WSMan -ComputerName <target> -Credential (Get-Credential)
```

## How to add in Prooflayer

System-UI → **Admin** → **Credentials** → **Add credential**:

1. **Name**: descriptive (e.g. `windows-fci-hosts`)
2. **Kind**: WinRM password
3. **Username**: `CONTOSO\svc-prooflayer` (or `svc-prooflayer@contoso.local`
   or `WORKGROUP\prooflayer` for a local account)
4. **Password**: paste
5. **Metadata**: set `domain` and any notes

## Rotation

Rotation cadence follows AD password policy or org password rotation
SLA. For service accounts, longer-lived passwords are common (90-365
days) provided the account is locked-down (no interactive logon, no
internet-facing services, etc.).

Steps:
1. Reset the password in AD: `Set-ADAccountPassword -Identity svc-prooflayer -Reset -NewPassword (Read-Host -AsSecureString)`
2. Paste new password into Prooflayer's Rotate flow
3. Verify a scan succeeds with the new credential

For dual-key rotation (rare with passwords): impossible without
two accounts. AD doesn't support multiple active passwords per account.

## Failure modes (anticipated)

| Symptom                                      | Likely cause                                                               |
|---                                           |---                                                                         |
| `WSManFault: Access is denied`                | Wrong password, or user not in `Remote Management Users` on the target     |
| `WSManFault: Cannot find the computer`        | Hostname resolution fails, or target's WinRM listener isn't running        |
| `Kerberos authentication error: Clock skew`   | Target host's clock differs from KDC by >5 min                              |
| Scan succeeds for some hosts, fails for others | Domain trust topology — user account isn't trusted by the target's domain  |

## Security notes

- Password is held as role-scoped plaintext at rest (no app-layer encryption), never logged.
- For high-sensitivity environments, prefer Kerberos auth + a Group
  Managed Service Account (gMSA) — passwords managed by AD, rotated
  every 30 days, never visible to admins. The current
  `winrm_password` payload doesn't support gMSA flows; that's a
  future credential variant when needed.
- Enforce `AllowUnencrypted = $false` on the target's WinRM service —
  if a Basic-auth-over-HTTP listener exists, the password traverses
  the network in plaintext.
- Audit `wsmprovhost.exe` startup events on target hosts via the UAL or
  Sysmon to track Prooflayer scan activity.
