variable "subscription_id" {
  description = "Subscription ID where the Reader role is assigned. Defaults to the active az login subscription."
  type        = string
  default     = null
}

variable "spn_display_name" {
  description = "Display name for the AD application + service principal."
  type        = string
  default     = "prooflayer-scanner"
}

variable "delegated_spn_display_name" {
  description = <<-EOT
    Display name for the SECOND app registration used for delegated
    (refresh-token) auth — the path that reaches Exchange-backed
    Purview surfaces (retention labels, DLP, audit log search,
    eDiscovery) that app-only auth can't.
  EOT
  type        = string
  default     = "prooflayer-scanner-delegated"
}

variable "pwsh_spn_display_name" {
  description = <<-EOT
    Display name for the THIRD app registration used for cert-based
    app-only PowerShell auth — drives Connect-IPPSSession against
    the Security & Compliance Center backend for surfaces only
    reachable via PowerShell (DLP policies, mailbox audit config,
    audit retention policies, etc.).

    Distinct from the delegated SPN because Microsoft requires
    separate confidential-client app regs for cert auth vs the
    public-client device-code refresh-token flow.
  EOT
  type        = string
  default     = "prooflayer-scanner-pwsh"
}

variable "pwsh_cert_validity_hours" {
  description = <<-EOT
    Validity period for the self-signed cert bound to the
    prooflayer-scanner-pwsh app registration. Default 1 year
    (8760 hours). To rotate: bump this value, re-apply terraform,
    pull the new outputs, paste into the Prooflayer credential
    (rotate-credential flow).

    Microsoft accepts certs up to ~24 months; longer than that
    starts hitting CA-signing-anchor lifetime checks even though
    self-signed is fine in principle.
  EOT
  type        = number
  default     = 8760
}

variable "graph_delegated_permissions" {
  description = <<-EOT
    Microsoft Graph DELEGATED permissions to request on the delegated
    app registration AND grant tenant-wide admin consent for. Each name
    must be a key in `delegated.tf`'s `local.graph_delegated_scopes`
    map — add an entry to that map first if a permission you need is
    not listed.

    `offline_access` is required: without it, the OAuth server won't
    issue a refresh_token, and the entire delegated-credential pattern
    breaks down. Don't remove it.

    Default set covers retention labels (the unlock that motivated
    building this credential type). Extend as later phases add
    Exchange-backed compliance discovery (DLP, audit logs, eDiscovery).
  EOT
  type        = list(string)
  default = [
    # Foundation — required for any delegated flow
    "offline_access",             # REQUIRED — without it, no refresh token issued
    "User.Read",                  # minimum delegated scope every Graph call needs

    # Phase 7 — Records management
    "RecordsManagement.Read.All", # retention labels + retention events / event types

    # Phase 8 — broader Purview / compliance surface
    "eDiscovery.Read.All",        # /security/cases/ediscoveryCases
    "AuditLogsQuery.Read.All",    # /security/auditLog/queries (saved audit queries)
  ]
}

variable "role" {
  description = "Built-in Azure RBAC role assigned at the subscription scope."
  type        = string
  default     = "Reader"
}

variable "secret_validity_months" {
  description = "Lifetime of the client secret in months. Re-applying after this rotates the secret."
  type        = number
  default     = 12
}

variable "graph_application_permissions" {
  description = <<-EOT
    Microsoft Graph application permissions to request on the app
    registration AND grant admin consent for. Each name must be a key
    in main.tf's `local.graph_app_roles` map. Add a new entry to that
    map first if a permission you need isn't listed.

    Default set covers Phase 1 M365 discovery (Users / Groups / Devices).
    Extend for later phases:
      - Conditional Access:  + "Policy.Read.All"
      - Intune:              + "DeviceManagementManagedDevices.Read.All", "DeviceManagementConfiguration.Read.All"
      - Purview:             + "InformationProtectionPolicy.Read.All"
      - SharePoint:          + "Sites.Read.All"
      - Teams:               + "Team.ReadBasic.All"
      - Audit logs:          + "AuditLog.Read.All"
  EOT
  type        = list(string)
  default = [
    # Phase 1 — Identity core
    "User.Read.All",
    "Group.Read.All",
    "Device.Read.All",
    # AuditLog.Read.All gates the `signInActivity` field on /users —
    # required because the discoverer projects it. Drop only if you also
    # remove signInActivity from discover_m365.rs $select.
    "AuditLog.Read.All",

    # Phase 2 — Access controls (Entra P2)
    "Policy.Read.All",

    # Phase 3 — Intune (Microsoft Endpoint Manager)
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementConfiguration.Read.All",

    # Phase 4 — Purview (Information Protection)
    # Used for sensitivity labels at the beta endpoint.
    "InformationProtectionPolicy.Read.All",

    # Phase 5 — Collaboration (SharePoint + Teams)
    "Sites.Read.All",
    "Team.ReadBasic.All",

    # Phase 6 — Posture deepening
    "DeviceManagementApps.Read.All",       # /deviceAppManagement/*ManagedAppProtections
    "BitlockerKey.ReadBasic.All",          # /informationProtection/bitlocker/recoveryKeys
    "DeviceLocalCredential.ReadBasic.All", # /directory/deviceLocalCredentials (LAPS)
    "RoleManagement.Read.Directory",       # /roleManagement/directory/* (PIM eligibility)
    "RecordsManagement.Read.All",          # /security/labels/retentionLabels (beta)
    # No new permission needed for:
    #   - extensionAttributes on /devices (covered by existing Device.Read.All)
    #   - assignedLicenses on /users (covered by existing User.Read.All)
    #   - /deviceManagement/deviceCategories (covered by existing DeviceManagementConfiguration.Read.All)
    #   - /identity/conditionalAccess/authenticationContextClassReferences (covered by existing Policy.Read.All)

    # Phase 7 — Access surface completion
    "Application.Read.All", # /servicePrincipals + /applications
    # No new permission needed for:
    #   - /directoryRoles                                  (covered by RoleManagement.Read.Directory)
    #   - /roleManagement/directory/roleAssignments        (covered by RoleManagement.Read.Directory)

    # Phase 8 — Security posture
    "SecurityEvents.Read.All",         # /security/secureScores (Microsoft Secure Score)
    "Policy.Read.AuthenticationMethod", # /policies/authenticationMethodsPolicy/authenticationMethodConfigurations
    "UserAuthenticationMethod.Read.All", # /users/{id}/authentication/methods (per-user MFA registration — m365_user_auth_methods_scoped)
    # No new permission needed for:
    #   - /identity/conditionalAccess/namedLocations  (covered by Policy.Read.All)
  ]
}
