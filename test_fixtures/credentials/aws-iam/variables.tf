variable "credential_kind" {
  description = <<-EOT
    Which AWS credential shape to provision:
      - "assume_role"  (default, recommended): create an IAM role that
        Prooflayer assumes via STS. Trust policy gates the assumption on
        a trusted principal + required external_id. The Prooflayer VM's
        own instance role is the source identity in production.
      - "access_key": create an IAM user + programmatic access keys.
        Faster bootstrap for dev/POC scenarios, but produces long-lived
        secrets that must be rotated by re-applying.
  EOT
  type        = string
  default     = "assume_role"

  validation {
    condition     = contains(["assume_role", "access_key"], var.credential_kind)
    error_message = "credential_kind must be \"assume_role\" or \"access_key\"."
  }
}

variable "iam_name" {
  description = "Base name for the IAM role or user. Suffix matches the credential_kind."
  type        = string
  default     = "prooflayer-scanner"
}

variable "region" {
  description = "AWS region passed through to the Prooflayer credential as default region metadata. Doesn't restrict where the role can scan."
  type        = string
  default     = "us-east-1"
}

variable "managed_policy_arns" {
  description = <<-EOT
    Managed policy ARNs to attach. Defaults:
      - SecurityAudit                       — read-only access scoped for
                                              security assessments;
                                              equivalent to Azure Reader.
      - AWSResourceExplorerReadOnlyAccess   — Resource Explorer Search +
                                              GetView; required for the
                                              discovery sweep.

    To extend (e.g. add data-plane S3 reads or KMS GetKeyPolicy details
    that SecurityAudit doesn't cover), add additional ARNs here.
  EOT
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/SecurityAudit",
    "arn:aws:iam::aws:policy/AWSResourceExplorerReadOnlyAccess",
  ]
}

# -----------------------------------------------------------------------------
# assume_role mode only
# -----------------------------------------------------------------------------

variable "trusted_principal_arns" {
  description = <<-EOT
    Principals allowed to call AssumeRole on the scanner role. Used only
    when credential_kind = "assume_role".

    Defaults to the current AWS account root (`arn:aws:iam::<account>:root`),
    which lets any IAM user/role in the same account assume — easiest
    path when Prooflayer runs inside the customer's own account on an EC2
    instance with an instance role.

    For cross-account SaaS deployments, set this to the Prooflayer SaaS
    AWS account ID's root, e.g. `["arn:aws:iam::123456789012:root"]`.
  EOT
  type        = list(string)
  default     = []
}

variable "external_id" {
  description = <<-EOT
    External ID required on every AssumeRole call. AWS's confused-deputy
    protection mechanism — every third-party scanner (Datadog, Wiz,
    Lacework, …) requires this. Used only when credential_kind = "assume_role".

    Leave empty to auto-generate a random 32-char string. Once generated,
    paste it into Prooflayer's credential form alongside the role ARN.
  EOT
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# access_key mode only
# -----------------------------------------------------------------------------

variable "key_validity_months" {
  description = "Lifetime of the access key in months before terraform apply rotates it. access_key mode only."
  type        = number
  default     = 12
}
