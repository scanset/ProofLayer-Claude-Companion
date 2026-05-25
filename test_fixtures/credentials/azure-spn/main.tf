# =============================================================================
# Prooflayer scanning SPN
#
# Provisions:
#   - An Entra ID application (app registration)
#   - A service principal in the tenant
#   - A rotating client secret
#   - A Reader role assignment at the subscription scope
#
# Auth: uses your existing `az login` context. No Terraform-side credentials.
#
# After `terraform apply`, run `terraform output` to get the values you paste
# into Prooflayer's Credentials → "Add credential" form (kind: Azure SPN).
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azuread" {}

provider "azurerm" {
  features {}
  # If var.subscription_id is null, azurerm uses the current az login context.
  subscription_id = var.subscription_id
}

# -----------------------------------------------------------------------------
# Discover the active subscription + tenant from the az login context.
# -----------------------------------------------------------------------------

data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

# Microsoft Graph as a service principal in the tenant. Used as the
# `resource_object_id` for app-role grants below — the same way the
# "Grant admin consent" button in the portal works under the hood.
data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

locals {
  subscription_id = coalesce(var.subscription_id, data.azurerm_subscription.current.subscription_id)
  tenant_id       = data.azuread_client_config.current.tenant_id

  # Well-known Microsoft Graph application-role IDs.
  # Verify any of these with: `az ad sp show --id 00000003-0000-0000-c000-000000000000 --query "appRoles[?value=='<name>'].id"`
  # The mapping is global across all tenants; these ids are public.
  graph_app_roles = {
    "User.Read.All"                           = "df021288-bdef-4463-88db-98f22de89214"
    "Group.Read.All"                          = "5b567255-7703-4780-807c-7be8301ae99b"
    "Device.Read.All"                         = "7438b122-aefc-4978-80ed-43db9fcc7715"
    "Policy.Read.All"                         = "246dd0d5-5bd0-4def-940b-0421030a5b68"
    "DeviceManagementManagedDevices.Read.All" = "2f51be20-0bb4-4fed-bf7b-db946066c75e"
    "DeviceManagementConfiguration.Read.All"  = "dc377aa6-52d8-4e23-b271-2a7ae04cedf3"
    "InformationProtectionPolicy.Read.All"    = "19da66cb-0fb0-4390-b071-ebc76a349482"
    "Sites.Read.All"                          = "332a536c-c7ef-4017-ab91-336970924f0d"
    "Team.ReadBasic.All"                      = "2280dda6-0bfd-44ee-a2f4-cb867cfc4c1e"
    "AuditLog.Read.All"                       = "b0afded3-3588-46d8-8b3d-9842eff778da"

    # Phase 6 additions — VERIFY each id against your tenant before apply:
    #   az ad sp show --id 00000003-0000-0000-c000-000000000000 \
    #     --query "appRoles[?value=='<NAME>' && contains(allowedMemberTypes,'Application')].id" -o tsv
    #
    # Best-guess IDs from Microsoft Learn — these are global constants
    # but verify after the Sites.Read.All off-by-one-hex incident in
    # earlier rollout. If any apply fails with "Permission being assigned
    # was not found on application", run the lookup and patch the id here.
    "DeviceManagementApps.Read.All"       = "7a6ee1e7-141e-4cec-ae74-d9db155731ff"
    "BitlockerKey.ReadBasic.All"          = "f690d423-6b29-4d04-98c6-694c42282419"
    "DeviceLocalCredential.ReadBasic.All" = "db51be59-e728-414b-b800-e0f010df1a79"
    "RoleManagement.Read.Directory"       = "483bed4a-2ad3-4361-a73b-c83ccdbdc53c"
    "RecordsManagement.Read.All"          = "ac3a2b8e-03a3-4da9-9ce0-cbe28bf1accd"

    # Phase 7 — Access surface completion. VERIFY before apply:
    #   az ad sp show --id 00000003-0000-0000-c000-000000000000 \
    #     --query "appRoles[?value=='Application.Read.All' && contains(allowedMemberTypes,'Application')].id" -o tsv
    # Application.Read.All covers BOTH /servicePrincipals and /applications.
    # No new permission needed for /directoryRoles or /roleManagement/directory/roleAssignments
    # — both are covered by the existing RoleManagement.Read.Directory.
    "Application.Read.All" = "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"

    # Phase 8 — Security posture (Microsoft Secure Score). VERIFY before apply:
    #   az ad sp show --id 00000003-0000-0000-c000-000000000000 \
    #     --query "appRoles[?value=='SecurityEvents.Read.All' && contains(allowedMemberTypes,'Application')].id" -o tsv
    # Gates the /security/secureScores endpoint that the secure_scores
    # GraphPath in discover_m365.rs reads. Without it the path returns
    # 403 and the discoverer skips it (sweep continues, but no
    # M365::SecureScore asset materializes).
    "SecurityEvents.Read.All" = "bf394140-e372-4bf9-a898-299cfc7564e5"

    # Phase 8b — Authentication methods policy. VERIFY before apply:
    #   az ad sp show --id 00000003-0000-0000-c000-000000000000 \
    #     --query "appRoles[?value=='Policy.Read.AuthenticationMethod' && contains(allowedMemberTypes,'Application')].id" -o tsv
    # Gates /policies/authenticationMethodsPolicy/authenticationMethodConfigurations.
    # Policy.Read.All does NOT cover this endpoint — Microsoft Graph
    # stratifies the authentication-method policy surface under its own
    # narrower scope (same pattern as the Sites.Read.All vs. broader
    # directory permissions split). Without it the path returns 403
    # and the auth_method_configurations GraphPath silently skips.
    "Policy.Read.AuthenticationMethod" = "8e3bc81b-d2f3-4b7b-838c-32c88218d2f0"

    # Phase 8c — Per-user registered authentication methods. VERIFY before apply:
    #   az ad sp show --id 00000003-0000-0000-c000-000000000000 \
    #     --query "appRoles[?value=='UserAuthenticationMethod.Read.All' && contains(allowedMemberTypes,'Application')].id" -o tsv
    # Gates GET /users/{id}/authentication/methods — the live per-user MFA
    # method inventory the m365_user_auth_methods_scoped CTN reads. This is
    # the registered-methods read, distinct from Policy.Read.AuthenticationMethod
    # (which only covers tenant authentication-method *policy*, not per-user
    # registrations). Sensitive permission: exposes phone numbers / authenticator
    # detail, so expect extra scrutiny at consent.
    "UserAuthenticationMethod.Read.All" = "38d9df27-64da-44fd-b7c5-a6fbac20248f"
  }
}

# -----------------------------------------------------------------------------
# AD application + service principal
#
# `required_resource_access` declares the Microsoft Graph permissions the
# app needs. These show up in the portal's "API permissions" list but
# are *requested* only — the per-permission azuread_app_role_assignment
# resources below grant them (admin consent equivalent).
#
# Default set covers Phase 1 M365 discovery (Users / Groups / Devices).
# Extend var.graph_application_permissions to add more (Conditional
# Access, Intune, Purview, SharePoint, Teams). See the azure_spn credential reference (../../credentials/azure_spn.md).
# -----------------------------------------------------------------------------

resource "azuread_application" "scanner" {
  display_name = var.spn_display_name

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    dynamic "resource_access" {
      for_each = toset(var.graph_application_permissions)
      content {
        id   = local.graph_app_roles[resource_access.value]
        type = "Role" # "Role" = Application permission; "Scope" = Delegated.
      }
    }
  }
}

resource "azuread_service_principal" "scanner" {
  client_id = azuread_application.scanner.client_id

  # `enterprise = true` surfaces the SPN under Entra → Enterprise
  # applications so portal role assignment (Compliance Administrator,
  # etc.) can find it via the standard member-picker search. With
  # `enterprise = false` the SPN still exists in the directory (it
  # holds Graph permissions etc.) but is hidden from that UI view.
  # The flag has no effect on the SPN's identity, credentials, or
  # appRoleAssignments — only its UI surfacing.
  feature_tags {
    enterprise = true
    gallery    = false
  }
}

# -----------------------------------------------------------------------------
# Admin consent for the Microsoft Graph application permissions.
#
# Each azuread_app_role_assignment is the Terraform-native equivalent of
# clicking "Grant admin consent for <tenant>" in the portal. Without
# these, the requested permissions stay in "Not granted" state and Graph
# returns 403 Authorization_RequestDenied — which is exactly what the
# scanner hit on first M365 discovery.
#
# The principal running `terraform apply` needs Cloud Application
# Administrator (or higher) to create these grants. Reader / Contributor
# alone is not enough — those are Azure RBAC roles, not Entra ID roles.
# -----------------------------------------------------------------------------

resource "azuread_app_role_assignment" "graph_perms" {
  for_each = toset(var.graph_application_permissions)

  app_role_id         = local.graph_app_roles[each.value]
  principal_object_id = azuread_service_principal.scanner.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# -----------------------------------------------------------------------------
# Client secret — auto-rotates on the configured interval
# -----------------------------------------------------------------------------

resource "time_rotating" "scanner_secret" {
  rotation_months = var.secret_validity_months
}

resource "azuread_application_password" "scanner" {
  application_id = azuread_application.scanner.id
  display_name   = "prooflayer-scanner"

  rotate_when_changed = {
    rotation = time_rotating.scanner_secret.id
  }
}

# -----------------------------------------------------------------------------
# RBAC — Reader at subscription scope
#
# Reader covers the ARM read calls the cloud-native scanner makes for
# CIS / STIG benchmarks: VM, storage, NSG, Key Vault metadata, etc.
#
# To extend coverage:
#   - Storage data plane: add a separate role_assignment with
#     "Storage Blob Data Reader" at storage account scope
#   - Key Vault secret metadata: add "Key Vault Reader" at vault scope
#   - Security recommendations: add "Security Reader" at subscription scope
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "scanner_reader" {
  scope                = "/subscriptions/${local.subscription_id}"
  role_definition_name = var.role
  principal_id         = azuread_service_principal.scanner.object_id
}
