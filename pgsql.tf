################################################################################
## Public Network
################################################################################
resource "random_password" "pgsql_admin_login" {
  length  = 14
  special = false
  upper   = false
}

resource "random_password" "pgsql_admin_password" {
  length = 24
}

resource "azurerm_postgresql_flexible_server" "public" {
  name                   = "public"
  resource_group_name    = data.azurerm_resource_group.public_prod.name
  location               = var.location
  administrator_login    = "psqladmin${random_password.pgsql_admin_login.result}"
  administrator_password = random_password.pgsql_admin_password.result
  sku_name               = "B_Standard_B1ms" # 1vCore / 2 Gb - https://docs.microsoft.com/en-us/azure/virtual-machines/sizes-b-series-burstable
  storage_mb             = "32768"
  version                = "13"
  zone                   = "1"
}
