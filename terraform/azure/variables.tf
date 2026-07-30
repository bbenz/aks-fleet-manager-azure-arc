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

variable "location" {
  description = <<-EOT
    Azure region for all resources. Defaults to eastus2 (broad AKS/Fleet
    Manager availability, competitive pricing). Automatically overridden by
    scripts/02-select-regions.ps1's generated tfvars when region
    auto-discovery runs - see terraform.tfvars.example.
  EOT
  type        = string
  default     = "eastus2"
}

variable "expected_tenant_id" {
  description = "Optional safety check: if set, refuses to apply unless the active az CLI tenant matches this exact tenant ID."
  type        = string
  default     = null
}

variable "expected_subscription_id" {
  description = "Optional safety check: if set, refuses to apply unless the active az CLI subscription matches this exact subscription ID."
  type        = string
  default     = null
}

variable "aks_node_vm_size" {
  description = "VM size for the AKS default (system) node pool. Standard_D2s_v3 comfortably runs all 11 Online Boutique services + Redis across 2 nodes."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_node_count" {
  description = "Fixed node count for the AKS default node pool. Autoscaling is intentionally disabled by default for predictable demo cost - raise this or set aks_autoscaling_enabled if you need headroom."
  type        = number
  default     = 2

  validation {
    condition     = var.aks_node_count >= 1 && var.aks_node_count <= 10
    error_message = "aks_node_count must be between 1 and 10 for this demo."
  }
}

variable "aks_autoscaling_enabled" {
  description = "Enable the Kubernetes cluster autoscaler on the default node pool. When true, aks_node_count becomes the initial count and aks_min_count/aks_max_count set the bounds."
  type        = bool
  default     = false
}

variable "aks_min_count" {
  description = "Minimum node count when aks_autoscaling_enabled = true."
  type        = number
  default     = 1
}

variable "aks_max_count" {
  description = "Maximum node count when aks_autoscaling_enabled = true."
  type        = number
  default     = 3
}

variable "aks_sku_tier" {
  description = "AKS control plane SKU tier. Free avoids the Uptime SLA charge that Standard/Premium add - appropriate for a demo, not for production."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be one of: Free, Standard, Premium."
  }
}

variable "fleet_hub_vm_size" {
  description = "VM size for the Fleet Manager hub cluster's single system node. Standard_D2s_v3 is the smallest size used in Microsoft's own Terraform quickstart - keeps the always-on hub cluster as small as Fleet Manager supports."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "enable_diagnostics" {
  description = "If true, creates a Log Analytics workspace and wires up AKS Container Insights + a diagnostic setting. Costs extra (Log Analytics ingestion/retention) - disabled by default to keep the demo cost-conscious."
  type        = bool
  default     = false
}
