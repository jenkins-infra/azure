# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

provider "postgresql" {
  # Configuration options
  host      = azurerm_postgresql_flexible_server.public.fqdn
  username  = local.public_pgsql_admin_login
  password  = random_password.pgsql_admin_password.result
  superuser = false
}

