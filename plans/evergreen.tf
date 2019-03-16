#
# This terraform plan defines the resources necessary to serve
# evergreen.jenkins.io and power the Jenkins Essentials effort
#

resource "azurerm_resource_group" "evergreen" {
  name     = "${var.prefix}-evergreen"
  location = "East US 2"
}

resource "azurerm_postgresql_server" "evergreen" {
  name                = "${var.prefix}-evergreen-db"
  location            = "${azurerm_resource_group.evergreen.location}"
  resource_group_name = "${azurerm_resource_group.evergreen.name}"

  sku {
    name = "B_Gen4_2"
    capacity = 2
    tier = "Basic"
    family = "Gen4"
  }

  storage_profile {
    storage_mb = 5120
    backup_retention_days = 7
    geo_redundant_backup = "Disabled"
  }

  administrator_login = "evergreen_admin"
  # Once the infrastructure has been deployed, the password should be manually
  # reset such that it can be utilized in Kubernetes/Puppet/etc
  administrator_login_password = "${random_id.prefix.hex}A1!"
  version = "10.0"
  ssl_enforcement = "Disabled"
}

resource "azurerm_postgresql_database" "evergreen_prod" {
  name                = "evergreen_prod"
  resource_group_name = "${azurerm_resource_group.evergreen.name}"
  server_name         = "${azurerm_postgresql_server.evergreen.name}"
  charset             = "UTF8"
  collation           = "English_United States.1252"
}

