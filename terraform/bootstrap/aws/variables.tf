variable "create_state_backend" {
  description = "If true, creates an S3 bucket (versioned, encrypted, public access blocked) for aws remote state. Default false - this demo uses local state (see ../README.md)."
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Short prefix applied to every resource name (see .env NAME_PREFIX)."
  type        = string
  default     = "flarc"
}

variable "environment" {
  description = "Environment/lifecycle tag applied to every resource (see .env ENVIRONMENT)."
  type        = string
  default     = "demo"
}

variable "state_storage_suffix" {
  description = <<-EOT
    Required (non-empty) whenever create_state_backend is true. S3 bucket
    names must be globally unique across ALL of AWS, so
    name_prefix+environment alone cannot guarantee uniqueness. Set this to
    something unique to you, e.g. your account ID's first 8 characters.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.state_storage_suffix == "" || can(regex("^[a-z0-9-]{1,20}$", var.state_storage_suffix))
    error_message = "state_storage_suffix must be empty, or 1-20 lowercase alphanumeric/hyphen characters."
  }
}

variable "aws_region" {
  description = "AWS region for the state S3 bucket."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS CLI/SSO profile to use. Leave null to use the default credential provider chain."
  type        = string
  default     = null
}
