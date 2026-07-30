variable "create_state_backend" {
  description = "If true, creates an Azure Storage Account + container for azurerm remote state. Default false - this demo uses local state (see ../README.md)."
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
    Required (non-empty) whenever create_state_backend is true. Storage
    account names must be globally unique across ALL of Azure, so
    name_prefix+environment alone cannot guarantee uniqueness. Set this to
    something unique to you, e.g. your subscription ID's first 8 characters.
    Lowercase alphanumeric only - Azure Storage Account names cap at 24
    total characters.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.state_storage_suffix == "" || can(regex("^[a-z0-9]{1,12}$", var.state_storage_suffix))
    error_message = "state_storage_suffix must be empty, or 1-12 lowercase alphanumeric characters."
  }
}

variable "azure_subscription_id" {
  description = "Azure subscription ID to create the state storage account in. Leave null to use the active `az login` context's subscription."
  type        = string
  default     = null
}

variable "azure_location" {
  description = "Azure region for the state storage account."
  type        = string
  default     = "eastus2"
}
