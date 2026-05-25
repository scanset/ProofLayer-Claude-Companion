output "region" {
  description = "Region the hosts live in."
  value       = var.region
}

# ---- SSH credential material (for an `ssh_key` credential) -------------------

output "ssh_private_key_pem" {
  description = <<-EOT
    The GENERATED SSH private key, PEM. Paste this into Prooflayer as an
    `ssh_key` credential. Export with:
      terraform output -raw ssh_private_key_pem
    (or download the file at `ssh_key_file` below).
  EOT
  value       = tls_private_key.eval.private_key_pem
  sensitive   = true
}

output "ssh_key_file" {
  description = "Path to the private key written to disk (chmod 600) — download/upload this if you'd rather not copy from the terminal."
  value       = local_file.private_key.filename
}

output "ssh_public_key" {
  description = "The public half (already installed on the Linux hosts)."
  value       = tls_private_key.eval.public_key_openssh
}

# ---- Windows credential material (for a `winrm_password` credential) ---------

output "windows_username" {
  description = "WinRM username for the Windows host."
  value       = "Administrator"
}

output "windows_password" {
  description = "GENERATED Windows Administrator password. Export with: terraform output -raw windows_password"
  value       = random_password.windows_admin.result
  sensitive   = true
}

# ---- The hosts (register these, or let AWS discovery enumerate them) ---------

output "hosts" {
  description = "The three scan targets: OS, channel, login user, and reachable address."
  value = {
    ubuntu = {
      os          = "ubuntu22"
      channel     = "ssh"
      ssh_user    = "ubuntu"
      public_ip   = aws_instance.ubuntu.public_ip
      public_dns  = aws_instance.ubuntu.public_dns
      instance_id = aws_instance.ubuntu.id
    }
    rocky9 = {
      os          = "rocky9"
      channel     = "ssh"
      ssh_user    = "rocky"
      public_ip   = aws_instance.rocky.public_ip
      public_dns  = aws_instance.rocky.public_dns
      instance_id = aws_instance.rocky.id
    }
    windows = {
      os          = "windows_server"
      channel     = "winrm"
      winrm_user  = "Administrator"
      public_ip   = aws_instance.windows.public_ip
      public_dns  = aws_instance.windows.public_dns
      instance_id = aws_instance.windows.id
    }
  }
}

# ---- Graph context (what discovery should link them under) -------------------

output "vpc_id" {
  description = "The VPC the three hosts share — discovery links them under it (VPC contains subnet contains instances)."
  value       = aws_vpc.eval.id
}

output "subnet_id" {
  description = "The shared public subnet."
  value       = aws_subnet.eval.id
}
