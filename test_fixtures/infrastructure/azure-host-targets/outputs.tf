output "location" {
  description = "Region the VMs live in."
  value       = var.location
}

output "resource_group_name" {
  description = "The resource group containing all three VMs — discovery links them under it."
  value       = azurerm_resource_group.eval.name
}

# ---- SSH credential material (for an `ssh_key` credential) -------------------

output "ssh_private_key_pem" {
  description = <<-EOT
    The GENERATED SSH private key, PEM. Paste this into Prooflayer as an
    `ssh_key` credential. Export with:
      terraform output -raw ssh_private_key_pem
    (or download the file at `ssh_key_file`).
  EOT
  value       = tls_private_key.eval.private_key_pem
  sensitive   = true
}

output "ssh_key_file" {
  description = "Path to the private key written to disk (chmod 600) — download/upload this if you'd rather not copy from the terminal."
  value       = local_file.private_key.filename
}

output "ssh_public_key" {
  description = "The public half (installed on both Linux VMs)."
  value       = tls_private_key.eval.public_key_openssh
}

# ---- Windows credential material (for a `winrm_password` credential) ---------

output "windows_username" {
  description = "WinRM username for the Windows VM."
  value       = var.windows_admin_username
}

output "windows_password" {
  description = "GENERATED Windows admin password. Export with: terraform output -raw windows_password"
  value       = random_password.windows_admin.result
  sensitive   = true
}

# ---- The hosts (register these, or let Azure discovery enumerate them) -------

output "hosts" {
  description = "The three scan targets: OS, channel, login user, and public IP."
  value = {
    ubuntu = {
      os        = "ubuntu22"
      channel   = "ssh"
      ssh_user  = var.linux_admin_username
      public_ip = azurerm_public_ip.eval["ubuntu"].ip_address
      vm_id     = azurerm_linux_virtual_machine.ubuntu.id
    }
    rhel9 = {
      os        = "rhel9"
      channel   = "ssh"
      ssh_user  = var.linux_admin_username
      public_ip = azurerm_public_ip.eval["rhel9"].ip_address
      vm_id     = azurerm_linux_virtual_machine.rhel9.id
    }
    windows = {
      os         = "windows_server"
      channel    = "winrm"
      winrm_user = var.windows_admin_username
      public_ip  = azurerm_public_ip.eval["windows"].ip_address
      vm_id      = azurerm_windows_virtual_machine.windows.id
    }
  }
}

output "vnet_id" {
  description = "The shared VNet — discovery links the VMs under the RG and this network."
  value       = azurerm_virtual_network.eval.id
}
