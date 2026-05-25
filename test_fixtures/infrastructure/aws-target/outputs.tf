output "region" {
  description = "Region the buckets live in — use as the credential's default region metadata."
  value       = var.region
}

output "compliant_bucket" {
  description = "Bucket expected to PASS the aws_s3_bucket policy (encrypted, versioned, locked down, TLS-only)."
  value       = aws_s3_bucket.compliant.bucket
}

output "drift_bucket" {
  description = "Bucket expected to FAIL (no default encryption, versioning off, public-access block disabled)."
  value       = aws_s3_bucket.drift.bucket
}

output "register_as_assets" {
  description = "The two bucket names to register/scan in Prooflayer (or let AWS discovery enumerate them)."
  value       = [aws_s3_bucket.compliant.bucket, aws_s3_bucket.drift.bucket]
}
