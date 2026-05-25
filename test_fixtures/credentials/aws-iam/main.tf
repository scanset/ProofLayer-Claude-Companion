# =============================================================================
# Prooflayer scanning IAM principal
#
# Provisions either:
#   - An IAM role that Prooflayer assumes via STS (credential_kind = "assume_role")
#   - An IAM user with programmatic access keys (credential_kind = "access_key")
#
# Auth: uses your existing AWS credentials (AWS_PROFILE / aws sso login / env).
# No Terraform-side credentials needed.
#
# After `terraform apply`, run `terraform output` to get the values you paste
# into Prooflayer's Credentials → "Add credential" form.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  is_assume_role = var.credential_kind == "assume_role"
  is_access_key  = var.credential_kind == "access_key"

  # Default trusted principal: the current account's root. This lets
  # the Prooflayer VM's instance role (and any other IAM principal in
  # the same account) call AssumeRole. For cross-account SaaS, override
  # via var.trusted_principal_arns.
  effective_trusted_principals = (
    length(var.trusted_principal_arns) > 0
    ? var.trusted_principal_arns
    : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
  )
}

# -----------------------------------------------------------------------------
# assume_role mode — IAM role with trust policy + external_id
# -----------------------------------------------------------------------------

resource "random_string" "external_id" {
  count   = local.is_assume_role && var.external_id == "" ? 1 : 0
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

locals {
  effective_external_id = (
    local.is_assume_role
    ? (var.external_id != "" ? var.external_id : try(random_string.external_id[0].result, ""))
    : ""
  )
}

data "aws_iam_policy_document" "scanner_trust" {
  count = local.is_assume_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.effective_trusted_principals
    }

    # Confused-deputy protection: every AssumeRole call must present
    # the external_id. Prooflayer stores it alongside the role ARN in
    # the credential payload and includes it on every STS call.
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.effective_external_id]
    }
  }
}

resource "aws_iam_role" "scanner" {
  count                = local.is_assume_role ? 1 : 0
  name                 = var.iam_name
  assume_role_policy   = data.aws_iam_policy_document.scanner_trust[0].json
  max_session_duration = 3600
  description          = "Prooflayer scanner - assumed by the Prooflayer VM to read AWS resources for compliance scans."
}

resource "aws_iam_role_policy_attachment" "scanner_role" {
  for_each = local.is_assume_role ? toset(var.managed_policy_arns) : toset([])

  role       = aws_iam_role.scanner[0].name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# access_key mode — IAM user with rotating programmatic access keys
# -----------------------------------------------------------------------------

resource "aws_iam_user" "scanner" {
  count = local.is_access_key ? 1 : 0
  name  = var.iam_name
  tags = {
    purpose = "prooflayer-scanner"
  }
}

resource "aws_iam_user_policy_attachment" "scanner_user" {
  for_each = local.is_access_key ? toset(var.managed_policy_arns) : toset([])

  user       = aws_iam_user.scanner[0].name
  policy_arn = each.value
}

resource "time_rotating" "scanner_key" {
  count           = local.is_access_key ? 1 : 0
  rotation_months = var.key_validity_months
}

resource "aws_iam_access_key" "scanner" {
  count = local.is_access_key ? 1 : 0
  user  = aws_iam_user.scanner[0].name

  lifecycle {
    replace_triggered_by = [time_rotating.scanner_key[0].id]
  }
}
