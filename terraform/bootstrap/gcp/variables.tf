variable "create_state_backend" {
  description = "If true, creates a GCS bucket (versioned) for gcs remote state. Default false - this demo uses local state (see ../README.md)."
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
    Required (non-empty) whenever create_state_backend is true. GCS bucket
    names must be globally unique across ALL of GCP, so
    name_prefix+environment alone cannot guarantee uniqueness. Set this to
    something unique to you, e.g. your project ID's first 8 characters.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.state_storage_suffix == "" || can(regex("^[a-z0-9-]{1,20}$", var.state_storage_suffix))
    error_message = "state_storage_suffix must be empty, or 1-20 lowercase alphanumeric/hyphen characters."
  }
}

variable "gcp_project_id" {
  description = "GCP project ID to create the state GCS bucket in (see .env GCP_PROJECT_ID)."
  type        = string
  default     = null
}

variable "gcp_region" {
  description = "GCP region for the state GCS bucket."
  type        = string
  default     = "us-central1"
}

variable "gcp_impersonate_service_account" {
  description = "Optional service account email to impersonate (see .env GCP_IMPERSONATE_SERVICE_ACCOUNT). Leave null to use the active `gcloud auth application-default login` identity directly."
  type        = string
  default     = null
}
