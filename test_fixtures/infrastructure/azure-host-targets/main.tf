# =============================================================================
# Prooflayer host-channel test targets (Azure) — Ubuntu + RHEL 9 + Windows
# =============================================================================
# The Azure twin of ../host-targets (AWS). Stands up three real VMs in ONE
# resource group + VNet so the resource-group hierarchy gives discovery a clean
# tree to link:  Subscription → Resource Group → (VNet/Subnet, the three VMs,
# their NICs + public IPs).
#
#   - Ubuntu 22.04   → scan over `ssh`   (platform `ubuntu` policies)
#   - RHEL 9         → scan over `ssh`   (platform `rhel9`/`rocky9` policies)
#   - Windows Server → scan over `winrm` (platform `windows` policies)
#
# Terraform GENERATES the SSH keypair — export the private key (paste or
# download) into an `ssh_key` credential. The Windows admin password is
# generated and exposed as a sensitive output for a `winrm_password` credential.
#
# REAL, BILLABLE resources (3 small VMs). `terraform destroy` when done. Auth
# uses your ambient `az login` context (or set subscription_id). Eval-grade only.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.100" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
    local   = { source = "hashicorp/local", version = "~> 2.0" }
    random  = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "azurerm" {
  features {}
  # Empty = ambient `az login` / env context. Set to target a specific sub.
  subscription_id = var.subscription_id != "" ? var.subscription_id : null
}

locals {
  common_tags = merge({ "prooflayer:fixture" = "azure-host-targets" }, var.tags)
}

# -----------------------------------------------------------------------------
# Generated SSH keypair — private key is a sensitive output AND written to disk
# so you can paste or download it into the credential DB.
# -----------------------------------------------------------------------------
resource "tls_private_key" "eval" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.eval.private_key_pem
  filename        = "${path.module}/${var.name_prefix}-key.pem"
  file_permission = "0600"
}

# Windows admin password — generated, exposed as a sensitive output.
# special=false keeps it clear of PowerShell quoting while still meeting Windows
# complexity (upper + lower + digit = 3 of 4 categories).
resource "random_password" "windows_admin" {
  length  = 20
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# -----------------------------------------------------------------------------
# Resource group + network. The RG is the containment root discovery links under.
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "eval" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "eval" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.eval.name
  location            = azurerm_resource_group.eval.location
  address_space       = ["10.30.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "eval" {
  name                 = "${var.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.eval.name
  virtual_network_name = azurerm_virtual_network.eval.name
  address_prefixes     = ["10.30.1.0/24"]
}

resource "azurerm_network_security_group" "eval" {
  name                = "${var.name_prefix}-nsg"
  resource_group_name = azurerm_resource_group.eval.name
  location            = azurerm_resource_group.eval.location
  tags                = local.common_tags

  security_rule {
    name                       = "ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "winrm"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985-5986"
    source_address_prefix      = var.allowed_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "eval" {
  subnet_id                 = azurerm_subnet.eval.id
  network_security_group_id = azurerm_network_security_group.eval.id
}

# -----------------------------------------------------------------------------
# Per-VM public IP + NIC. One module-free loop would be cleaner, but spelling
# the three out keeps the fixture readable.
# -----------------------------------------------------------------------------
locals {
  hosts = toset(["ubuntu", "rhel9", "windows"])
}

resource "azurerm_public_ip" "eval" {
  for_each            = local.hosts
  name                = "${var.name_prefix}-${each.key}-pip"
  resource_group_name = azurerm_resource_group.eval.name
  location            = azurerm_resource_group.eval.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "eval" {
  for_each            = local.hosts
  name                = "${var.name_prefix}-${each.key}-nic"
  resource_group_name = azurerm_resource_group.eval.name
  location            = azurerm_resource_group.eval.location
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.eval.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.eval[each.key].id
  }
}

# -----------------------------------------------------------------------------
# Linux VMs (Ubuntu + RHEL 9) — SSH key auth, password auth disabled.
# -----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "ubuntu" {
  name                  = "${var.name_prefix}-ubuntu"
  resource_group_name   = azurerm_resource_group.eval.name
  location              = azurerm_resource_group.eval.location
  size                  = var.linux_vm_size
  admin_username        = var.linux_admin_username
  network_interface_ids = [azurerm_network_interface.eval["ubuntu"].id]

  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = tls_private_key.eval.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(local.common_tags, { "prooflayer:os" = "ubuntu22" })
}

resource "azurerm_linux_virtual_machine" "rhel9" {
  name                  = "${var.name_prefix}-rhel9"
  resource_group_name   = azurerm_resource_group.eval.name
  location              = azurerm_resource_group.eval.location
  size                  = var.linux_vm_size
  admin_username        = var.linux_admin_username
  network_interface_ids = [azurerm_network_interface.eval["rhel9"].id]

  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = tls_private_key.eval.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # First-party RHEL 9 (PAYG, no Marketplace agreement needed). For Rocky 9
  # instead, point these at the resf Rocky image + add an
  # azurerm_marketplace_agreement and a `plan` block.
  source_image_reference {
    publisher = var.rhel_publisher
    offer     = var.rhel_offer
    sku       = var.rhel_sku
    version   = "latest"
  }

  tags = merge(local.common_tags, { "prooflayer:os" = "rhel9" })
}

# -----------------------------------------------------------------------------
# Windows VM — password auth; a CustomScript extension turns on WinRM basic/HTTP.
# -----------------------------------------------------------------------------
resource "azurerm_windows_virtual_machine" "windows" {
  name                  = "${var.name_prefix}-win"
  resource_group_name   = azurerm_resource_group.eval.name
  location              = azurerm_resource_group.eval.location
  size                  = var.windows_vm_size
  admin_username        = var.windows_admin_username
  admin_password        = random_password.windows_admin.result
  network_interface_ids = [azurerm_network_interface.eval["windows"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  tags = merge(local.common_tags, { "prooflayer:os" = "windows_server" })
}

# Enable WinRM basic-auth over HTTP (eval-only) once the VM is up.
resource "azurerm_virtual_machine_extension" "winrm" {
  name                       = "enable-winrm"
  virtual_machine_id         = azurerm_windows_virtual_machine.windows.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = join(" ", [
      "powershell -ExecutionPolicy Unrestricted -Command",
      "\"winrm quickconfig -quiet;",
      "winrm set winrm/config/service '@{AllowUnencrypted=\\\"true\\\"}';",
      "winrm set winrm/config/service/auth '@{Basic=\\\"true\\\"}';",
      "New-NetFirewallRule -DisplayName 'WinRM-HTTP' -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow\""
    ])
  })
}
