variable "region" {
  description = "AWS region to create the buckets in."
  type        = string
  default     = "us-east-1"
}

variable "profile" {
  description = "Optional AWS CLI named profile. Empty = use ambient credentials (env vars / shared config / instance role)."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix for the two bucket names. A random suffix is appended for global uniqueness."
  type        = string
  default     = "prooflayer-eval"
}

variable "tags" {
  description = "Extra tags applied to both buckets."
  type        = map(string)
  default     = {}
}
