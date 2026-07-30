# Both providers rely on the active `az login` session (Azure CLI auth) -
# no client secret/certificate/service principal is configured here.
# See docs/AUTHENTICATION-AND-PERMISSIONS.md.
provider "azurerm" {
  features {}
}

provider "azapi" {}
