# =============================================================================
# Prooflayer test target — minimal Azure resources for end-to-end smoke testing
#
# Provisions:
#   - A resource group
#   - A storage account with compliant settings (TLS 1.2 min, HTTPS-only)
#
# This is what the test ESP policy scans against. After `terraform apply`,
# pass `storage_account_name` from the output into the policy file before
# running the test scan.
#
# Auth: uses your existing `az login` context (same as the azure-spn fixture).
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_subscription" "current" {}

locals {
  subscription_id = coalesce(var.subscription_id, data.azurerm_subscription.current.subscription_id)
}

# -----------------------------------------------------------------------------
# Random suffix — storage account names are globally unique across Azure.
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 3
}

# -----------------------------------------------------------------------------
# Resource group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "test" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    purpose = "prooflayer-smoke-test"
  }
}

# -----------------------------------------------------------------------------
# Storage account — provisioned to PASS a compliance scan.
#
# To produce a FAILING scan instead, override:
#   terraform apply \
#     -var='https_only=false' \
#     -var='min_tls=TLS1_0'
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "test" {
  name                       = "${var.storage_name_prefix}${random_id.suffix.hex}"
  resource_group_name        = azurerm_resource_group.test.name
  location                   = azurerm_resource_group.test.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"

  # Compliance-relevant settings — the test policy verifies these.
  https_traffic_only_enabled      = var.https_only
  min_tls_version                 = var.min_tls
  allow_nested_items_to_be_public = false

  tags = {
    purpose = "prooflayer-smoke-test"
  }
}
