#
# This terraform plan defines the resources necessary for the uplink service
#

# This random value is generated once, stored in the state file and only changed
# when 'uplink_db_password_id' is modified
# cfr. https://www.terraform.io/docs/providers/random/index.html
resource "random_string" "uplink_db_password" {
  length = 16

  keepers = {
    id = var.uplink_db_password_id
  }
}

resource "azurerm_resource_group" "uplink" {
  name     = "${var.prefix}uplink"
  location = var.location

  tags = {
    env = var.prefix
  }
}

resource "azurerm_postgresql_server" "uplink" {
  name                = "${var.prefix}uplink"
  location            = azurerm_resource_group.uplink.location
  resource_group_name = azurerm_resource_group.uplink.name

  sku_name = "B_Gen5_2"

  storage_profile {
    storage_mb            = 46080
    backup_retention_days = 7
    geo_redundant_backup  = "Disabled"
  }

  administrator_login          = "uplinkadmin"
  administrator_login_password = random_string.uplink_db_password.result
  version                      = "10.0"
  ssl_enforcement              = "Disabled"
}

resource "azurerm_postgresql_database" "uplink" {
  name                = "uplink"
  resource_group_name = azurerm_resource_group.uplink.name
  server_name         = azurerm_postgresql_server.uplink.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
}

