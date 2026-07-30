output "resource_group_name" {
  description = "Resource group containing AKS, Fleet Manager, and (post Arc-onboarding) the Arc-connected EKS/GKE cluster resources."
  value       = azurerm_resource_group.demo.name
}

output "location" {
  description = "Azure region used for all resources in this root."
  value       = azurerm_resource_group.demo.location
}

output "aks_cluster_name" {
  description = "AKS cluster name - used by `az aks get-credentials`."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  description = "Full ARM resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.id
}

output "fleet_name" {
  description = "Fleet Manager name."
  value       = azapi_resource.fleet.name
}

output "fleet_id" {
  description = "Full ARM resource ID of the Fleet Manager (with hub cluster)."
  value       = azapi_resource.fleet.id
}

output "tenant_id" {
  description = "Active Azure AD tenant ID (from the az CLI session used to apply)."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Active Azure subscription ID (from the az CLI session used to apply)."
  value       = data.azurerm_client_config.current.subscription_id
}

output "arc_resource_group" {
  description = "Resource group to pass to `az connectedk8s connect --resource-group` when onboarding the EKS and GKE clusters (same RG as everything else in this demo)."
  value       = azurerm_resource_group.demo.name
}

output "kubeconfig_command" {
  description = "Command to fetch this cluster's kubeconfig into the fleet_manager-arc-demo-wide 'aks-demo' context. Not run automatically by Terraform - scripts/04-apply.ps1 runs it after apply."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.demo.name} --name ${azurerm_kubernetes_cluster.aks.name} --context aks-demo --overwrite-existing"
}

# NOTE: kube_config / kube_config_raw are intentionally NOT re-exposed as
# outputs here (they already exist in Terraform state on the
# azurerm_kubernetes_cluster resource itself, which is an unavoidable,
# documented exposure - see docs/OPERATIONS.md - but this file avoids
# widening that exposure further via `terraform output -json`).
