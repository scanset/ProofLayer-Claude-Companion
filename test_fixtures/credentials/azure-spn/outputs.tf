# =============================================================================
# Outputs — paste these into Prooflayer's Credentials form
#
#   Kind:           Azure SPN
#   Client ID:      <client_id>
#   Tenant ID:      <tenant_id>
#   Client secret:  <client_secret>  (sensitive)
#
# Metadata fields:
#   subscription_id = <subscription_id>
#
# Reveal client_secret with:  terraform output -raw client_secret
# =============================================================================

output "client_id" {
  description = "Azure AD application client ID — paste into Prooflayer's `client_id` field."
  value       = azuread_application.scanner.client_id
}

output "tenant_id" {
  description = "Entra ID tenant ID — paste into Prooflayer's `tenant_id` field."
  value       = local.tenant_id
}

output "client_secret" {
  description = "Generated client secret. Use `terraform output -raw client_secret` to reveal."
  value       = azuread_application_password.scanner.value
  sensitive   = true
}

output "subscription_id" {
  description = "Subscription the SPN has Reader on — set as metadata key `subscription_id`."
  value       = local.subscription_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal — useful when adding more role assignments out-of-band."
  value       = azuread_service_principal.scanner.object_id
}

output "secret_expires_at" {
  description = "When the current client secret expires."
  value       = azuread_application_password.scanner.end_date
}

# -----------------------------------------------------------------------------
# Delegated (refresh-token) credential outputs
#
# Used to bootstrap a `M365DelegatedRefresh` credential in Prooflayer.
# The refresh_token itself is NOT terraform-managed — it's captured by
# the Prooflayer enrollment UI via device-code flow against this
# client_id, then stored in the credential vault.
#
# Bootstrap flow once these values are in place:
#   1. terraform apply (produces the delegated_client_id below)
#   2. In Prooflayer: Credentials → Add → M365 Delegated → paste client_id
#      and tenant_id
#   3. Prooflayer kicks a device-code flow against this app reg
#   4. Admin user signs in via browser, refresh token is captured
#   5. Credential is live; m365_graph_query collector can use it for
#      retention-label discovery
# -----------------------------------------------------------------------------

output "delegated_client_id" {
  description = "Client ID of the delegated (refresh-token) app registration. Paste into Prooflayer's M365 Delegated credential form."
  value       = azuread_application.scanner_delegated.client_id
}

output "delegated_service_principal_object_id" {
  description = "Object ID of the delegated SPN. Useful when adding more role assignments to the delegated principal."
  value       = azuread_service_principal.scanner_delegated.object_id
}

# -----------------------------------------------------------------------------
# PowerShell cert-based credential outputs
#
# Used to bootstrap an `AzureSpnCert` credential in Prooflayer. The
# certificate is non-secret (PEM-encoded public cert), the private key
# IS secret and stored in terraform state — pull via
# `terraform output -raw pwsh_private_key` and paste into Prooflayer's
# credential form (same paste-the-PEM flow as the ssh_key credential
# kind).
#
# Operator flow:
#   1. terraform apply
#   2. terraform output -raw pwsh_certificate    # → paste into Cert field
#   3. terraform output -raw pwsh_private_key    # → paste into Key field
#   4. terraform output pwsh_client_id           # → paste into Client ID field
#   5. terraform output tenant_id                # → paste into Tenant ID field
#
# Post-apply, the cert exists on the SPN but the SPN is NOT yet in any
# Security & Compliance role group. That one-time step is manual via
# Connect-IPPSSession + Add-RoleGroupMember (Microsoft hasn't exposed
# role-group membership as a terraform-manageable resource).
# -----------------------------------------------------------------------------

output "pwsh_client_id" {
  description = "Client ID of the PowerShell (cert-based) app registration. Paste into the Prooflayer credential form."
  value       = azuread_application.scanner_pwsh.client_id
}

output "pwsh_service_principal_object_id" {
  description = "Object ID of the PowerShell SPN. Use this with `Add-RoleGroupMember -Member <object_id>` from Connect-IPPSSession to grant the SPN compliance read access."
  value       = azuread_service_principal.scanner_pwsh.object_id
}

output "pwsh_certificate" {
  description = "PEM-encoded public certificate bound to the PowerShell SPN. Paste into Prooflayer's credential form (Cert field). Non-secret."
  value       = tls_self_signed_cert.scanner_pwsh.cert_pem
}

output "pwsh_private_key" {
  description = "PEM-encoded private key for the PowerShell SPN cert. Paste into Prooflayer's credential form (Key field). SENSITIVE — store immediately in the credential vault, do NOT commit to git."
  value       = tls_private_key.scanner_pwsh.private_key_pem
  sensitive   = true
}

output "pwsh_cert_expires_at" {
  description = "ISO-8601 expiry of the cert. Prooflayer's credential rotation reminder watches this."
  value       = tls_self_signed_cert.scanner_pwsh.validity_end_time
}
