# Azure root: AKS cluster + Fleet Manager (with hub cluster) + AKS's own
# Fleet membership. Arc-connecting the EKS/GKE clusters and joining THEM to
# the Fleet is handled imperatively by scripts/05-connect-arc.ps1 and
# scripts/06-join-fleet.ps1 (see docs/ARCHITECTURE.md for why that boundary
# exists - short version: `az connectedk8s connect` bootstraps Arc identity
# and must run after the foreign cluster already exists, so it can't be
# sequenced inside a single `terraform apply` here).
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.80.0, < 5.0.0"
    }
    azapi = {
      # azurerm_kubernetes_fleet_manager cannot create a hub cluster
      # (hub_profile is deprecated/ignored - see main.tf comment above the
      # azapi_resource.fleet block). azapi is required for that one resource.
      source  = "azure/azapi"
      version = ">= 2.0.0, < 3.0.0"
    }
  }

  # Local state by default for this demo repo. See docs/OPERATIONS.md for the
  # three documented remote-state migration strategies and the optional
  # terraform/bootstrap/ root if you choose to adopt remote state instead.
  # backend "azurerm" {}
}
