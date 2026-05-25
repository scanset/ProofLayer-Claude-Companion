variable "location" {
  description = "Azure region for the resource group and VMs."
  type        = string
  default     = "eastus"
}

variable "subscription_id" {
  description = "Optional subscription id. Empty = ambient `az login` / env context."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix for every resource name (RG, VNet, VMs, key file)."
  type        = string
  default     = "prooflayer-eval"
}

variable "allowed_cidr" {
  description = <<-EOT
    CIDR allowed inbound to SSH (22) and WinRM (5985-5986). Defaults to the whole
    internet for a throwaway eval — SET THIS to the appliance's public egress IP
    (e.g. "203.0.113.4/32") for anything longer-lived.
  EOT
  type        = string
  default     = "0.0.0.0/0"
}

variable "linux_vm_size" {
  description = "VM size for the Ubuntu and RHEL hosts."
  type        = string
  default     = "Standard_B1s"
}

variable "windows_vm_size" {
  description = "VM size for the Windows host (needs >= 2 GB RAM)."
  type        = string
  default     = "Standard_B2s"
}

variable "linux_admin_username" {
  description = "Admin (and SSH) username for the Linux VMs."
  type        = string
  default     = "azureuser"
}

variable "windows_admin_username" {
  description = "Admin (WinRM) username for the Windows VM. Must not be 'admin'/'administrator'."
  type        = string
  default     = "azureadmin"
}

variable "rhel_publisher" {
  description = "RPM-host image publisher. Default = first-party RHEL 9 (no Marketplace agreement)."
  type        = string
  default     = "RedHat"
}

variable "rhel_offer" {
  description = "RPM-host image offer."
  type        = string
  default     = "RHEL"
}

variable "rhel_sku" {
  description = "RPM-host image SKU (RHEL 9, LVM, Gen2)."
  type        = string
  default     = "9-lvm-gen2"
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
