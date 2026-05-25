# =============================================================================
# Outputs — paste these into Prooflayer's Credentials form
#
# assume_role mode (kind: AWS Role):
#   role_arn:     <role_arn>
#   external_id:  <external_id>
#   region:       <region> (metadata)
#
# access_key mode (kind: AWS Access Key):
#   access_key_id:      <access_key_id>
#   secret_access_key:  <secret_access_key>  (sensitive)
#   region:             <region> (metadata)
#
# Reveal sensitive values with:  terraform output -raw <name>
# =============================================================================

output "credential_kind" {
  description = "Which credential shape this apply produced — `assume_role` or `access_key`. Tells you which other outputs are populated."
  value       = var.credential_kind
}

output "region" {
  description = "Default AWS region — paste into Prooflayer credential metadata key `region`."
  value       = var.region
}

output "account_id" {
  description = "AWS account ID the role/user lives in — informational, useful for credential naming."
  value       = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# assume_role outputs
# -----------------------------------------------------------------------------

output "role_arn" {
  description = "IAM role ARN — paste into Prooflayer's `role_arn` field. Empty in access_key mode."
  value       = local.is_assume_role ? aws_iam_role.scanner[0].arn : ""
}

output "external_id" {
  description = "External ID required on AssumeRole — paste into Prooflayer's `external_id` field. Empty in access_key mode."
  value       = local.effective_external_id
  sensitive   = true
}

output "trusted_principals" {
  description = "Principals the role trusts — informational."
  value       = local.is_assume_role ? local.effective_trusted_principals : []
}

# -----------------------------------------------------------------------------
# access_key outputs
# -----------------------------------------------------------------------------

output "access_key_id" {
  description = "Access key ID — paste into Prooflayer's `access_key_id` field. Empty in assume_role mode."
  value       = local.is_access_key ? aws_iam_access_key.scanner[0].id : ""
}

output "secret_access_key" {
  description = "Secret access key. Reveal with `terraform output -raw secret_access_key`. Empty in assume_role mode."
  value       = local.is_access_key ? aws_iam_access_key.scanner[0].secret : ""
  sensitive   = true
}

output "iam_user_arn" {
  description = "IAM user ARN — informational. Empty in assume_role mode."
  value       = local.is_access_key ? aws_iam_user.scanner[0].arn : ""
}
