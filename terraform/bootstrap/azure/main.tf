resource "azurerm_resource_group" "state" {
  count = var.create_state_backend ? 1 : 0

  name     = "${var.name_prefix}-${var.environment}-tfstate-rg"
  location = var.azure_location

  tags = {
    project    = "fleet-arc-demo"
    managed_by = "terraform-bootstrap"
  }
}

resource "azurerm_storage_account" "state" {
  count = var.create_state_backend ? 1 : 0

  # Storage account names: 3-24 chars, lowercase alphanumeric only, globally
  # unique across ALL of Azure - hence the required state_storage_suffix.
  name                     = substr("${var.name_prefix}${var.environment}tfstate${var.state_storage_suffix}", 0, 24)
  resource_group_name      = azurerm_resource_group.state[0].name
  location                 = azurerm_resource_group.state[0].location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  tags = {
    project    = "fleet-arc-demo"
    managed_by = "terraform-bootstrap"
  }
}

resource "azurerm_storage_container" "state" {
  count = var.create_state_backend ? 1 : 0

  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state[0].id
  container_access_type = "private"
}
