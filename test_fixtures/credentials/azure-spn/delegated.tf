# =============================================================================
# Prooflayer delegated (refresh-token) credential — sibling app registration
#
# Why a SECOND app registration:
#
# The scanner SPN in main.tf authenticates as an APPLICATION (client_credentials
# flow). That works for most Graph endpoints (~75% of M365 surface) but fails
# against the Purview / Records Management surfaces that proxy to Exchange
# Online — those endpoints do a secondary RBAC check against the principal,
# and Microsoft's Business Premium / Purview Suite tier doesn't reliably
# register SPNs in EXO's compliance role groups. Detailed breakdown in the
# parked retention_labels TODO at:
#     the M365 delegated-discovery path
#
# This second app registration is a PUBLIC CLIENT requesting DELEGATED Graph
# permissions. A human admin authenticates against it once via device-code
# flow, the resulting refresh_token gets stored in Prooflayer's credential
# vault, and the m365_graph_query collector mints fresh access tokens by
# refreshing as needed. The collector identifies the credential as
# delegated and uses the refresh_token OAuth2 flow instead of client_credentials.
#
# Auth chain at runtime:
#   refresh_token  -->  /token endpoint  -->  access_token (delegated)
#                                              + rotated refresh_token (persisted)
#   access_token   -->  Graph beta endpoint  -->  EXO compliance backend
#                                              -->  accepts delegated user context
#                                              -->  returns retention labels
#
# Once this app reg exists and is consented, Prooflayer's enrollment UI runs
# the device-code dance with this app's client_id, captures the refresh_token,
# and the m365_graph_query collector uses it for retention_labels / DLP /
# audit-log / eDiscovery / etc. (all the Exchange-backed compliance surfaces).
# =============================================================================

locals {
  # Well-known Microsoft Graph DELEGATED permission (oauth2PermissionScopes) IDs.
  # Verify any with:
  #   az ad sp show --id 00000003-0000-0000-c000-000000000000 \
  #     --query "oauth2PermissionScopes[?value=='<NAME>'].id" -o tsv
  #
  # These are global constants but verify after the Sites.Read.All
  # off-by-one-hex incident — copy/paste from MS Learn carries risk.
  graph_delegated_scopes = {
    # offline_access is REQUIRED for the auth server to return a refresh_token
    # at all. Without it, you get an access_token that expires in ~1hr and
    # no way to renew it unattended.
    "offline_access" = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"

    # User.Read is the minimum delegated scope every Graph delegated flow
    # needs. Microsoft auto-requires this; we list it explicitly so the
    # admin-consent grant covers it.
    "User.Read" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"

    # The actual unlock — delegated read of records management labels.
    # Global Graph permission id: 07f995eb-fc67-4522-ad66-2b8ca8ea3efd
    "RecordsManagement.Read.All" = "07f995eb-fc67-4522-ad66-2b8ca8ea3efd"

    # Phase 8 — broader Purview / compliance surface. Each was verified
    # against the tenant via `az ad sp show` lookup against Microsoft
    # Graph's oauth2PermissionScopes catalog.
    #
    # eDiscovery.Read.All — reads /security/cases/ediscoveryCases and
    #   related custodian / preservation / search objects. Standard
    #   legal-hold / discovery audit evidence.
    "eDiscovery.Read.All" = "99201db3-7652-4d5a-809a-bdb94f85fe3c"

    # AuditLogsQuery.Read.All — reads /security/auditLog/queries (saved
    #   audit-log search query definitions, NOT the audit log itself —
    #   that's a separate ingest path). Maps to AU-2 / AU-12 evidence
    #   ("we have queries that monitor for X event").
    "AuditLogsQuery.Read.All" = "1d9e7ac3-0eca-442c-82f9-e92625af6e6d"

    # NOT in the Microsoft Graph delegated catalog (verified via
    # `az ad sp show` returning empty):
    #   - DLP.Read.All           — DLP policies are still SCC PowerShell
    #                              only via Get-DlpCompliancePolicy
    #   - ComplianceManager.Read.All — Compliance Manager is portal-only
    # Both need to flow into Prooflayer via the manual-evidence path
    # (operator captures via PowerShell, uploads JSON via a future
    # M365::PowerShellEvidence pattern). Not buildable via Graph today.
  }
}

# -----------------------------------------------------------------------------
# Application: the delegated app registration
#
# `public_client.redirect_uris` set to Microsoft's standard nativeclient URI
# — required for device-code flow (no real redirect happens; the auth server
# uses the URI as an opaque identifier).
#
# `sign_in_audience = AzureADMyOrg` keeps this single-tenant. The refresh
# token issued against it can only be used to authenticate against THIS
# tenant — matches the security boundary of the credential.
# -----------------------------------------------------------------------------

resource "azuread_application" "scanner_delegated" {
  display_name     = var.delegated_spn_display_name
  sign_in_audience = "AzureADMyOrg"

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    dynamic "resource_access" {
      for_each = toset(var.graph_delegated_permissions)
      content {
        id   = local.graph_delegated_scopes[resource_access.value]
        type = "Scope" # "Scope" = Delegated permission; "Role" = Application
      }
    }
  }

  # Public client (no client secret) — required for device-code flow on
  # workloads that can't safely hold an app secret. The auth material is
  # the user's refresh token, held by Prooflayer's credential vault, NOT
  # an app-level secret.
  public_client {
    redirect_uris = [
      "https://login.microsoftonline.com/common/oauth2/nativeclient",
    ]
  }

  # `fallback_public_client_enabled = true` is what actually unlocks the
  # device-code flow. The `public_client` block above only enables
  # *interactive* public-client flows (loopback for native apps).
  # Without this flag, Microsoft treats the app as a confidential
  # client and the /token endpoint demands a client_secret —
  # failing device-code polls with:
  #     AADSTS7000218: "request body must contain the following
  #     parameter: 'client_assertion' or 'client_secret'"
  # This is the "Allow public client flows" toggle in the Entra portal
  # under Authentication → Advanced settings.
  fallback_public_client_enabled = true
}

resource "azuread_service_principal" "scanner_delegated" {
  client_id = azuread_application.scanner_delegated.client_id

  # `enterprise = true` so the SPN appears under Entra → Enterprise
  # applications. Same rationale as the app-only SPN — the portal
  # member-pickers gate on this for some role assignments.
  feature_tags {
    enterprise = true
    gallery    = false
  }
}

# -----------------------------------------------------------------------------
# Admin consent for the delegated scopes
#
# `azuread_service_principal_delegated_permission_grant` is the
# Terraform-native equivalent of "Grant admin consent for <tenant>" on a
# delegated permission set. This issues a TENANT-WIDE delegated permission
# grant — every user in the tenant can use these scopes against this app
# without their own consent prompt.
#
# (Without this, the first user to sign into the app would get a consent
# popup asking them to approve. That's fine for one user, hostile for
# rotation. The tenant-wide grant avoids it.)
#
# Note: this is ONE resource with a space-separated `claim_values` list, not
# one resource per scope (which is the pattern for `app_role_assignment`).
# Different shape because that's how the underlying Graph
# `/oauth2PermissionGrants` endpoint works.
# -----------------------------------------------------------------------------

resource "azuread_service_principal_delegated_permission_grant" "scanner_delegated" {
  service_principal_object_id          = azuread_service_principal.scanner_delegated.object_id
  resource_service_principal_object_id = data.azuread_service_principal.msgraph.object_id
  claim_values                         = var.graph_delegated_permissions
}
