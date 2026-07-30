data "azurerm_client_config" "current" {}

# Fails fast (before creating anything) if the active az CLI session isn't
# the tenant/subscription the operator expects - cheap insurance against
# accidentally deploying into the wrong subscription.
check "expected_azure_identity" {
  assert {
    condition = (
      var.expected_tenant_id == null ||
      data.azurerm_client_config.current.tenant_id == var.expected_tenant_id
    )
    error_message = "Active az CLI tenant (${data.azurerm_client_config.current.tenant_id}) does not match var.expected_tenant_id. Run `az login --tenant <id>` or `az account set --subscription <id>` first."
  }
  assert {
    condition = (
      var.expected_subscription_id == null ||
      data.azurerm_client_config.current.subscription_id == var.expected_subscription_id
    )
    error_message = "Active az CLI subscription (${data.azurerm_client_config.current.subscription_id}) does not match var.expected_subscription_id. Run `az account set --subscription <id>` first."
  }
}

locals {
  name_base = "${var.name_prefix}-${var.environment}"

  tags = merge(
    {
      owner       = var.owner
      project     = var.project
      environment = var.environment
      demo        = "fleet-arc-online-boutique"
      managed_by  = "terraform"
      cloud       = "azure"
    },
    var.expiration_date != null ? { expiration_date = var.expiration_date } : {}
  )
}

# --- Resource provider registration: deliberately NOT Terraform-managed ---
# Microsoft.ContainerService / Microsoft.Kubernetes / Microsoft.Kubernetes-
# Configuration / Microsoft.ExtendedLocation registration is checked (and, if
# missing, registered) imperatively by scripts/01-test-cloud-access.ps1 via
# `az provider register` - which is additive/non-destructive. Managing
# registration as an `azurerm_resource_provider_registration` resource here
# would mean `terraform destroy` (99-destroy-all.ps1) could UNREGISTER the
# provider subscription-wide on a SHARED subscription, breaking every other
# AKS/Arc workload other teams run in it. Not worth the risk for a demo repo.

resource "azurerm_resource_group" "demo" {
  name     = "${local.name_base}-rg"
  location = var.location
  tags     = local.tags
}

# --- AKS cluster ---
# Azure CNI Overlay (current recommended default, avoids classic Azure CNI's
# VNet IP exhaustion) with a managed AKS VNet - no custom VNet/subnet is
# created. This keeps the demo's networking footprint minimal while still
# using current, non-legacy defaults (kubenet is legacy; plain Azure CNI
# without overlay consumes one VNet IP per pod). See docs/ARCHITECTURE.md.
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${local.name_base}-aks"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  dns_prefix          = "${local.name_base}-aks"
  sku_tier            = var.aks_sku_tier

  default_node_pool {
    name                 = "system"
    vm_size              = var.aks_node_vm_size
    node_count           = var.aks_node_count
    auto_scaling_enabled = var.aks_autoscaling_enabled
    min_count            = var.aks_autoscaling_enabled ? var.aks_min_count : null
    max_count            = var.aks_autoscaling_enabled ? var.aks_max_count : null
    os_disk_size_gb      = 30

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }

  # Kubernetes-native RBAC (not Azure AD integration - that would require
  # admin_group_object_ids we don't have for a demo). local_account_disabled
  # stays false (default) so `az aks get-credentials` works immediately.
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  dynamic "oms_agent" {
    for_each = var.enable_diagnostics ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.aks[0].id
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [microsoft_defender]
  }
}

# --- Optional diagnostics (off by default - see var.enable_diagnostics) ---
resource "azurerm_log_analytics_workspace" "aks" {
  count               = var.enable_diagnostics ? 1 : 0
  name                = "${local.name_base}-logs"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.enable_diagnostics ? 1 : 0
  name                       = "${local.name_base}-aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks[0].id

  enabled_log {
    category = "kube-apiserver"
  }
  enabled_log {
    category = "kube-audit"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

# --- Fleet Manager WITH hub cluster ---
# azurerm_kubernetes_fleet_manager's `hub_profile` argument is deprecated and
# silently ignored by the provider (confirmed in provider source) - it can
# only create a hub-less Fleet. A hub cluster is required for
# ClusterResourcePlacement/ResourceOverride (this demo's entire mechanism for
# cloud-specific customization), so azapi is used instead, targeting the
# current stable ARM API version for fleets with a hub profile.
resource "azapi_resource" "fleet" {
  type      = "Microsoft.ContainerService/fleets@2025-03-01"
  name      = "${local.name_base}-fleet"
  location  = azurerm_resource_group.demo.location
  parent_id = azurerm_resource_group.demo.id
  tags      = local.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      hubProfile = {
        dnsPrefix = "${local.name_base}-fleet"
        agentProfile = {
          vmSize = var.fleet_hub_vm_size
        }
        apiServerAccessProfile = {
          enablePrivateCluster  = false
          enableVnetIntegration = false
        }
      }
    }
  }

  schema_validation_enabled = true
  response_export_values    = ["*"]
}

# --- AKS's own Fleet membership ---
# The EKS and GKE members are created later by scripts/06-join-fleet.ps1 (via
# `az fleet member create --member-cluster-id <Arc connectedCluster ARM ID>`)
# because their Arc connectedCluster resources don't exist until
# scripts/05-connect-arc.ps1 runs against each already-created foreign
# cluster - a cross-cloud, cross-script dependency Terraform can't express
# inside a single root's plan/apply.
resource "azurerm_kubernetes_fleet_member" "aks" {
  name                  = "aks-demo"
  kubernetes_fleet_id   = azapi_resource.fleet.id
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  group                 = "azure"
}
