# =============================================================================
# Outputs
#
# After apply:
#   terraform output                 # show all
#   terraform output -raw storage_account_name
#
# Paste storage_account_name and resource_group_name into the test ESP policy
# before running the test scan from the system UI.
# =============================================================================

output "subscription_id" {
  description = "Subscription the test target lives in."
  value       = local.subscription_id
}

output "resource_group_name" {
  description = "Resource group containing the test target."
  value       = azurerm_resource_group.test.name
}

output "storage_account_name" {
  description = "Storage account name. Globally unique — paste into the ESP policy's OBJECT block."
  value       = azurerm_storage_account.test.name
}

output "storage_account_id" {
  description = "Full ARM resource ID of the storage account. Useful when extending the policy."
  value       = azurerm_storage_account.test.id
}

output "settings_summary" {
  description = "Summary of the compliance-relevant settings on the storage account."
  value = {
    https_only      = azurerm_storage_account.test.https_traffic_only_enabled
    min_tls_version = azurerm_storage_account.test.min_tls_version
  }
}
