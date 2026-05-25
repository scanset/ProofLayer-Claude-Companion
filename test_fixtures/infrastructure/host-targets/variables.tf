variable "region" {
  description = "AWS region to create the hosts in."
  type        = string
  default     = "us-east-1"
}

variable "profile" {
  description = "Optional AWS CLI named profile. Empty = ambient credentials (env vars / shared config / instance role)."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix for every resource name (key pair, VPC, instances)."
  type        = string
  default     = "prooflayer-eval"
}

variable "allowed_cidr" {
  description = <<-EOT
    CIDR allowed to reach SSH (22) and WinRM (5985-5986) on the hosts.
    Defaults to the whole internet for a throwaway eval — SET THIS to the
    Prooflayer appliance's public egress IP (e.g. "203.0.113.4/32") for
    anything that lives longer than a demo.
  EOT
  type        = string
  default     = "0.0.0.0/0"
}

variable "linux_instance_type" {
  description = "Instance type for the Ubuntu and Rocky 9 hosts."
  type        = string
  default     = "t3.micro"
}

variable "windows_instance_type" {
  description = "Instance type for the Windows Server host (needs >= 2 GB RAM)."
  type        = string
  default     = "t3.small"
}

variable "ubuntu_ami" {
  description = "Override the Ubuntu 22.04 AMI id. Empty = newest Canonical jammy image in the region."
  type        = string
  default     = ""
}

variable "rocky_ami" {
  description = "Override the Rocky 9 AMI id. Empty = newest official Rocky-9-EC2-Base image. (For RHEL 9 instead, pass a RHEL AMI id here.)"
  type        = string
  default     = ""
}

variable "windows_ami" {
  description = "Override the Windows Server 2022 AMI id. Empty = newest Amazon Windows_Server-2022-English-Full-Base image."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
