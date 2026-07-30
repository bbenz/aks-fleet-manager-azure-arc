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
  description = "Project name used only for tagging, not in resource names (see .env PROJECT)."
  type        = string
  default     = "fleet-arc-demo"
}

variable "owner" {
  description = "Owner tag - who to contact about this deployment (see .env OWNER). Required so every resource is attributable."
  type        = string
}

variable "expiration_date" {
  description = "Informational expiration/teardown-by date tag, e.g. 2026-08-01 (see .env EXPIRATION_DATE). Purely advisory - does not auto-delete anything."
  type        = string
  default     = null
}

variable "region" {
  description = <<-EOT
    AWS region for all resources. Defaults to us-east-1 (broadest EKS/Spot
    availability, lowest historical pricing). Automatically overridden by
    scripts/02-select-regions.ps1's generated tfvars when region
    auto-discovery runs - see terraform.tfvars.example.
  EOT
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS CLI/SSO profile to use (see .env AWS_PROFILE). Leave null to use the default credential provider chain (env vars, default profile, or an assumed role via aws_assume_role_arn)."
  type        = string
  default     = null
}

variable "aws_assume_role_arn" {
  description = "Optional IAM role ARN to assume before creating resources (see .env AWS_ASSUME_ROLE_ARN). Useful for cross-account or least-privilege elevated-role workflows - see docs/AUTHENTICATION-AND-PERMISSIONS.md."
  type        = string
  default     = null
}

variable "expected_account_id" {
  description = "Optional safety check: if set, refuses to apply unless the active AWS credentials resolve to this exact 12-digit account ID."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the demo VPC."
  type        = string
  default     = "10.60.0.0/16"
}

variable "cluster_version" {
  description = "EKS Kubernetes version. 1.35 is Standard support (not the newest-and-riskiest, not approaching Standard-support expiry) as of this writing - see docs/ARCHITECTURE.md for the version-selection rationale and the recurring maintenance task of bumping this."
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group. t3.large (2 vCPU/8GB) is the documented sweet spot for the ~12-pod Online Boutique workload - t3.medium's 4GB is too tight once system pods are accounted for."
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 1 && var.node_desired_size <= 10
    error_message = "node_desired_size must be between 1 and 10 for this demo."
  }
}

variable "node_min_size" {
  description = "Minimum node count for the managed node group's scaling config."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum node count for the managed node group's scaling config."
  type        = number
  default     = 3
}

variable "node_capacity_type" {
  description = "ON_DEMAND (reliable, recommended for a live demo) or SPOT (substantially cheaper, risks a 2-minute-notice interruption mid-demo). See docs/ARCHITECTURE.md cost section."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "enable_aws_load_balancer_controller" {
  description = <<-EOT
    Install the AWS Load Balancer Controller via Helm + IRSA. Required for
    the frontend-external Service to get a modern Network Load Balancer;
    without it, a plain `type: LoadBalancer` Service falls back to the
    deprecated in-tree Classic Load Balancer provisioner. Disable only for
    troubleshooting - see docs/TROUBLESHOOTING.md.
  EOT
  type        = bool
  default     = true
}
