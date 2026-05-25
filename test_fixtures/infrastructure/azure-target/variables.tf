variable "subscription_id" {
  description = "Subscription where the test resources land. Defaults to active az login."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Resource group name for the test target."
  type        = string
  default     = "prooflayer-test-rg"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "storage_name_prefix" {
  description = "Prefix for the storage account name. Random hex suffix is appended to ensure global uniqueness. Must be 3-21 lowercase alphanumeric chars."
  type        = string
  default     = "pltest"

  validation {
    condition     = can(regex("^[a-z0-9]{3,21}$", var.storage_name_prefix))
    error_message = "storage_name_prefix must be 3-21 lowercase alphanumeric characters."
  }
}

# -----------------------------------------------------------------------------
# Knobs for flipping the storage account to a NON-compliant state — useful
# for verifying the policy correctly fails. Defaults are compliant.
# -----------------------------------------------------------------------------

variable "https_only" {
  description = "Require HTTPS for storage requests. Set false to produce a failing scan."
  type        = bool
  default     = true
}

variable "min_tls" {
  description = "Minimum TLS version. TLS1_2 is compliant; TLS1_0 / TLS1_1 should fail."
  type        = string
  default     = "TLS1_2"

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls)
    error_message = "min_tls must be one of TLS1_0, TLS1_1, TLS1_2."
  }
}
