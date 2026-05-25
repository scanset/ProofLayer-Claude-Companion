# =============================================================================
# Prooflayer host-channel test targets — Ubuntu + Rocky 9 + Windows Server
# =============================================================================
# Stands up three real hosts in one VPC so you can exercise the *host* channels
# (not just cloud control-plane / `local`):
#
#   - Ubuntu 22.04      → scan over `ssh`   (platform `ubuntu` policies)
#   - Rocky 9           → scan over `ssh`   (platform `rocky9`/`rhel9` policies)
#   - Windows Server    → scan over `winrm` (platform `windows` policies)
#
# Terraform GENERATES the SSH keypair — you export the private key (paste or
# download) and upload it into Prooflayer as an `ssh_key` credential. The Windows
# admin password is generated too and exposed as a (sensitive) output for a
# `winrm_password` credential.
#
# All three land in one VPC/subnet, so AWS discovery enumerates them and you can
# watch the asset graph link them (Account → VPC → Subnet → Instance).
#
# These are REAL, BILLABLE resources (3 small EC2 instances). `terraform destroy`
# when done. Auth uses your ambient AWS context (env vars / shared config /
# instance role). Eval-grade only — never reuse this key or these hosts anywhere
# real.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
    local  = { source = "hashicorp/local", version = "~> 2.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile != "" ? var.profile : null
}

locals {
  common_tags = merge({ "prooflayer:fixture" = "host-targets" }, var.tags)
}

# -----------------------------------------------------------------------------
# SSH keypair — GENERATED HERE. The private key is a sensitive output and is
# also written to disk so you can paste OR download it into the credential DB.
# -----------------------------------------------------------------------------
resource "tls_private_key" "eval" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "eval" {
  key_name   = "${var.name_prefix}-key"
  public_key = tls_private_key.eval.public_key_openssh
  tags       = local.common_tags
}

# Written next to the fixture (gitignored). `chmod 600` so ssh won't refuse it.
resource "local_file" "private_key" {
  content         = tls_private_key.eval.private_key_pem
  filename        = "${path.module}/${var.name_prefix}-key.pem"
  file_permission = "0600"
}

# Windows Administrator password — generated, exposed as a sensitive output.
# special=false keeps it clear of PowerShell/`net user` quoting while still
# meeting Windows complexity (upper + lower + digit = 3 of 4 categories).
resource "random_password" "windows_admin" {
  length  = 20
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# -----------------------------------------------------------------------------
# Network — one VPC, one public subnet, instances get public IPs so the
# appliance can reach them. (Lock `allowed_cidr` down to the appliance's egress
# IP in anything but a throwaway eval.)
# -----------------------------------------------------------------------------
resource "aws_vpc" "eval" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "eval" {
  vpc_id = aws_vpc.eval.id
  tags   = merge(local.common_tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "eval" {
  vpc_id                  = aws_vpc.eval.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${var.name_prefix}-subnet" })
}

resource "aws_route_table" "eval" {
  vpc_id = aws_vpc.eval.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eval.id
  }
  tags = merge(local.common_tags, { Name = "${var.name_prefix}-rt" })
}

resource "aws_route_table_association" "eval" {
  subnet_id      = aws_subnet.eval.id
  route_table_id = aws_route_table.eval.id
}

resource "aws_security_group" "eval" {
  name        = "${var.name_prefix}-sg"
  description = "Prooflayer host-targets: SSH + WinRM from the appliance"
  vpc_id      = aws_vpc.eval.id

  ingress {
    description = "SSH (Linux hosts)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    description = "WinRM HTTP (Windows host)"
    from_port   = 5985
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.name_prefix}-sg" })
}

# -----------------------------------------------------------------------------
# AMIs — newest official image per OS. Override with the *_ami vars if your
# region or account needs a specific id.
# -----------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  count       = var.ubuntu_ami == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_ami" "rocky" {
  count       = var.rocky_ami == "" ? 1 : 0
  most_recent = true
  owners      = ["792107900819"] # Rocky Enterprise Software Foundation
  filter {
    name   = "name"
    values = ["Rocky-9-EC2-Base-9.*-x86_64"]
  }
}

data "aws_ami" "windows" {
  count       = var.windows_ami == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

locals {
  ubuntu_ami  = var.ubuntu_ami != "" ? var.ubuntu_ami : data.aws_ami.ubuntu[0].id
  rocky_ami   = var.rocky_ami != "" ? var.rocky_ami : data.aws_ami.rocky[0].id
  windows_ami = var.windows_ami != "" ? var.windows_ami : data.aws_ami.windows[0].id

  # EC2Launch (Windows): set the Administrator password and turn on WinRM
  # basic-auth over HTTP. Eval-only — Basic + AllowUnencrypted is what the
  # `winrm` channel's basic mode expects; do NOT do this on a real host.
  windows_user_data = <<-PS1
    <powershell>
    net user Administrator "${random_password.windows_admin.result}"
    winrm quickconfig -quiet
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/service/auth '@{Basic="true"}'
    netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in action=allow protocol=TCP localport=5985
    </powershell>
  PS1
}

# -----------------------------------------------------------------------------
# Hosts
# -----------------------------------------------------------------------------
resource "aws_instance" "ubuntu" {
  ami                    = local.ubuntu_ami
  instance_type          = var.linux_instance_type
  key_name               = aws_key_pair.eval.key_name
  subnet_id              = aws_subnet.eval.id
  vpc_security_group_ids = [aws_security_group.eval.id]
  tags = merge(local.common_tags, {
    Name              = "${var.name_prefix}-ubuntu"
    "prooflayer:os"   = "ubuntu22"
    "prooflayer:user" = "ubuntu"
  })
}

resource "aws_instance" "rocky" {
  ami                    = local.rocky_ami
  instance_type          = var.linux_instance_type
  key_name               = aws_key_pair.eval.key_name
  subnet_id              = aws_subnet.eval.id
  vpc_security_group_ids = [aws_security_group.eval.id]
  tags = merge(local.common_tags, {
    Name              = "${var.name_prefix}-rocky9"
    "prooflayer:os"   = "rocky9"
    "prooflayer:user" = "rocky"
  })
}

resource "aws_instance" "windows" {
  ami                    = local.windows_ami
  instance_type          = var.windows_instance_type
  key_name               = aws_key_pair.eval.key_name
  subnet_id              = aws_subnet.eval.id
  vpc_security_group_ids = [aws_security_group.eval.id]
  user_data              = local.windows_user_data
  tags = merge(local.common_tags, {
    Name            = "${var.name_prefix}-winserver"
    "prooflayer:os" = "windows_server"
  })
}
