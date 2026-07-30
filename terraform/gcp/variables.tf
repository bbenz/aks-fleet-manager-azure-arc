variable "project_id" {
  description = "GCP project ID (see .env GCP_PROJECT_ID). Must already exist - this repo never creates or modifies GCP projects/billing."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase letters/digits/hyphens, starting with a letter)."
  }
}

variable "name_prefix" {
  description = "Short prefix applied to every resource name (see .env NAME_PREFIX)."
  type        = string
  default     = "flarc"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.name_prefix))
    error_message = "name_prefix must be 2-10 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Environment/lifecycle tag applied to every resource (see .env ENVIRONMENT)."
  type        = string
  default     = "demo"
}

variable "project" {
  description = "Project name used only for labeling, not in resource names (see .env PROJECT)."
  type        = string
  default     = "fleet-arc-demo"
}

variable "owner" {
  description = "Owner label - who to contact about this deployment (see .env OWNER). Required so every resource is attributable. Sanitized automatically for GCP's restrictive label-value charset (see locals.owner_label in main.tf)."
  type        = string
}

variable "expiration_date" {
  description = "Informational expiration/teardown-by date label, e.g. 2026-08-01 (see .env EXPIRATION_DATE). Purely advisory - does not auto-delete anything."
  type        = string
  default     = null
}

variable "region" {
  description = <<-EOT
    GCP region for the VPC subnet. Defaults to us-central1 (largest US
    region, broadest machine-type availability, matches upstream Online
    Boutique's own examples). Automatically overridden by
    scripts/02-select-regions.ps1's generated tfvars when region
    auto-discovery runs - see terraform.tfvars.example.
  EOT
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the zonal GKE cluster and its node pool. Must be within region. Defaults to us-central1-a."
  type        = string
  default     = "us-central1-a"
}

variable "gcp_impersonate_service_account" {
  description = "Optional service account email to impersonate for all GCP API calls (see .env GCP_IMPERSONATE_SERVICE_ACCOUNT). Leave null to use the active `gcloud auth application-default login` identity directly. See providers.tf and docs/AUTHENTICATION-AND-PERMISSIONS.md."
  type        = string
  default     = null
}

variable "subnet_cidr" {
  description = "Primary CIDR range for the GKE subnet (node IPs)."
  type        = string
  default     = "10.70.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for pod IPs (VPC-native alias IP allocation)."
  type        = string
  default     = "10.72.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR range for Kubernetes Service ClusterIPs (VPC-native alias IP allocation)."
  type        = string
  default     = "10.73.0.0/20"
}

variable "release_channel" {
  description = "GKE release channel. REGULAR is the recommended default (multiple upgrades/month, production-suitable)."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "machine_type" {
  description = "GCE machine type for GKE nodes. e2-standard-2 (2 vCPU/8GB) gives comfortable headroom for Online Boutique's adservice (JVM) - e2-medium's 4GB is documented to risk OOM."
  type        = string
  default     = "e2-standard-2"
}

variable "disk_type" {
  description = "Boot disk type for GKE nodes. pd-standard is the lowest-cost option and is sufficient for this demo workload."
  type        = string
  default     = "pd-standard"
}

variable "disk_size_gb" {
  description = "Boot disk size (GB) for GKE nodes."
  type        = number
  default     = 50
}

variable "node_min_count" {
  description = "Minimum nodes per zone for the node pool's autoscaling config."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum nodes per zone for the node pool's autoscaling config."
  type        = number
  default     = 4
}
