# =============================================================================
# Prooflayer AWS test target — minimal, drift-by-design
#
# Stands up two S3 buckets so a scan produces BOTH a pass and a fail:
#   - "${prefix}-compliant" : encrypted + versioned + public access blocked +
#                             TLS-only bucket policy           → should PASS
#   - "${prefix}-drift"     : no default encryption, versioning off,
#                             public access NOT blocked         → should FAIL
#
# Point Prooflayer at these with an `aws_access_key` / `aws_role` credential
# (provision one with the ../../credentials/aws-iam fixture) and the bundled
# `aws_s3_bucket` policy/CTN. Auth: your existing AWS CLI/profile context.
#
# Cheap to run; `terraform destroy` when done. These are real, billable
# resources (S3 storage is ~free at this size, but tear them down anyway).
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.region
  # Uses your ambient AWS credentials (env vars, shared config, or instance role).
  profile = var.profile != "" ? var.profile : null
}

# Suffix keeps bucket names globally unique without you having to pick one.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  compliant_name = "${var.name_prefix}-compliant-${random_string.suffix.result}"
  drift_name     = "${var.name_prefix}-drift-${random_string.suffix.result}"
  common_tags    = merge({ "prooflayer:fixture" = "aws-target" }, var.tags)
}

# -----------------------------------------------------------------------------
# COMPLIANT bucket — encrypted, versioned, locked down, TLS-only.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "compliant" {
  bucket        = local.compliant_name
  force_destroy = true
  tags          = merge(local.common_tags, { "prooflayer:expect" = "pass" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "compliant" {
  bucket = aws_s3_bucket.compliant.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "compliant" {
  bucket = aws_s3_bucket.compliant.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "compliant" {
  bucket                  = aws_s3_bucket.compliant.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "compliant_tls_only" {
  bucket = aws_s3_bucket.compliant.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.compliant.arn,
        "${aws_s3_bucket.compliant.arn}/*"
      ]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# -----------------------------------------------------------------------------
# DRIFT bucket — deliberately weak: no default encryption, versioning off,
# public-access block disabled. This is what the scan should flag.
# (No objects are made public; the *configuration* is the finding.)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "drift" {
  bucket        = local.drift_name
  force_destroy = true
  tags          = merge(local.common_tags, { "prooflayer:expect" = "fail" })
}

resource "aws_s3_bucket_public_access_block" "drift" {
  bucket                  = aws_s3_bucket.drift.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
