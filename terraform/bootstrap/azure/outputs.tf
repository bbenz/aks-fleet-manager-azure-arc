locals {
  backend_snippet = <<-EOT
    terraform {
      backend "azurerm" {
        resource_group_name  = "${var.create_state_backend ? azurerm_resource_group.state[0].name : ""}"
        storage_account_name = "${var.create_state_backend ? azurerm_storage_account.state[0].name : ""}"
        container_name       = "${var.create_state_backend ? azurerm_storage_container.state[0].name : ""}"
        key                  = "azure.tfstate"
      }
    }
  EOT
}

output "state_backend_config" {
  description = "Ready-to-paste azurerm backend block for terraform/azure/versions.tf, once create_state_backend = true has been applied."
  value       = var.create_state_backend ? local.backend_snippet : "create_state_backend is false - no backend created. This demo uses local state; see ../README.md."
}
