locals {
  azure_not_applied = "terraform/azure has not been applied yet - run scripts/03-init-plan.ps1 and scripts/04-apply.ps1 with ENABLE_AZURE=true first."
  aws_not_applied   = "terraform/aws has not been applied yet - run scripts/03-init-plan.ps1 and scripts/04-apply.ps1 with ENABLE_AWS=true first."
  gcp_not_applied   = "terraform/gcp has not been applied yet - run scripts/03-init-plan.ps1 and scripts/04-apply.ps1 with ENABLE_GCP=true first."
}

# --- Azure / AKS / Fleet Manager -------------------------------------------

output "azure_resource_group_name" {
  value = try(data.terraform_remote_state.azure[0].outputs.resource_group_name, local.azure_not_applied)
}

output "azure_location" {
  value = try(data.terraform_remote_state.azure[0].outputs.location, local.azure_not_applied)
}

output "aks_cluster_name" {
  value = try(data.terraform_remote_state.azure[0].outputs.aks_cluster_name, local.azure_not_applied)
}

output "fleet_name" {
  value = try(data.terraform_remote_state.azure[0].outputs.fleet_name, local.azure_not_applied)
}

output "fleet_id" {
  value = try(data.terraform_remote_state.azure[0].outputs.fleet_id, local.azure_not_applied)
}

output "arc_resource_group" {
  description = "Resource group to pass to `az connectedk8s connect --resource-group` when onboarding the EKS and GKE clusters."
  value       = try(data.terraform_remote_state.azure[0].outputs.arc_resource_group, local.azure_not_applied)
}

output "aks_kubeconfig_command" {
  value = try(data.terraform_remote_state.azure[0].outputs.kubeconfig_command, local.azure_not_applied)
}

# --- AWS / EKS ---------------------------------------------------------------

output "eks_cluster_name" {
  value = try(data.terraform_remote_state.aws[0].outputs.cluster_name, local.aws_not_applied)
}

output "aws_region" {
  value = try(data.terraform_remote_state.aws[0].outputs.region, local.aws_not_applied)
}

output "aws_account_id" {
  value = try(data.terraform_remote_state.aws[0].outputs.account_id, local.aws_not_applied)
}

output "eks_kubeconfig_command" {
  value = try(data.terraform_remote_state.aws[0].outputs.kubeconfig_command, local.aws_not_applied)
}

output "eks_connectedk8s_connect_command" {
  value = try(data.terraform_remote_state.aws[0].outputs.connectedk8s_connect_command, local.aws_not_applied)
}

# --- GCP / GKE -----------------------------------------------------------------

output "gke_cluster_name" {
  value = try(data.terraform_remote_state.gcp[0].outputs.cluster_name, local.gcp_not_applied)
}

output "gcp_project_id" {
  value = try(data.terraform_remote_state.gcp[0].outputs.project_id, local.gcp_not_applied)
}

output "gcp_region" {
  value = try(data.terraform_remote_state.gcp[0].outputs.region, local.gcp_not_applied)
}

output "gcp_zone" {
  value = try(data.terraform_remote_state.gcp[0].outputs.zone, local.gcp_not_applied)
}

output "gke_kubeconfig_command" {
  value = try(data.terraform_remote_state.gcp[0].outputs.kubeconfig_command, local.gcp_not_applied)
}

output "gke_kubeconfig_rename_context_command" {
  value = try(data.terraform_remote_state.gcp[0].outputs.kubeconfig_rename_context_command, local.gcp_not_applied)
}

output "gke_connectedk8s_connect_command" {
  value = try(data.terraform_remote_state.gcp[0].outputs.connectedk8s_connect_command, local.gcp_not_applied)
}

# --- Consolidated summary ------------------------------------------------------

output "summary" {
  description = "Single consolidated map of every value above - convenient for `terraform output -json summary` from scripts/08-validate-demo.ps1 and docs/DEMO-RUNSHEET.md."
  value = {
    azure = {
      resource_group_name = try(data.terraform_remote_state.azure[0].outputs.resource_group_name, null)
      location            = try(data.terraform_remote_state.azure[0].outputs.location, null)
      aks_cluster_name    = try(data.terraform_remote_state.azure[0].outputs.aks_cluster_name, null)
      fleet_name          = try(data.terraform_remote_state.azure[0].outputs.fleet_name, null)
      fleet_id            = try(data.terraform_remote_state.azure[0].outputs.fleet_id, null)
      kubeconfig_command  = try(data.terraform_remote_state.azure[0].outputs.kubeconfig_command, null)
      applied             = try(data.terraform_remote_state.azure[0].outputs.aks_cluster_name, null) != null
    }
    aws = {
      cluster_name       = try(data.terraform_remote_state.aws[0].outputs.cluster_name, null)
      region             = try(data.terraform_remote_state.aws[0].outputs.region, null)
      account_id         = try(data.terraform_remote_state.aws[0].outputs.account_id, null)
      kubeconfig_command = try(data.terraform_remote_state.aws[0].outputs.kubeconfig_command, null)
      applied            = try(data.terraform_remote_state.aws[0].outputs.cluster_name, null) != null
    }
    gcp = {
      cluster_name       = try(data.terraform_remote_state.gcp[0].outputs.cluster_name, null)
      project_id         = try(data.terraform_remote_state.gcp[0].outputs.project_id, null)
      region             = try(data.terraform_remote_state.gcp[0].outputs.region, null)
      zone               = try(data.terraform_remote_state.gcp[0].outputs.zone, null)
      kubeconfig_command = try(data.terraform_remote_state.gcp[0].outputs.kubeconfig_command, null)
      applied            = try(data.terraform_remote_state.gcp[0].outputs.cluster_name, null) != null
    }
  }
}
