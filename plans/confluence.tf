resource "azurerm_resource_group" "confluence" {
  name     = "${var.prefix}confluence"
  location = "${var.location}"
  tags {
      env = "${var.prefix}"
  }
}

resource "azurerm_mysql_server" "confluence" {
  name                = "${var.prefix}confluence"
  location            = "${azurerm_resource_group.confluence.location}"
  resource_group_name = "${azurerm_resource_group.confluence.name}"

  sku {
    name = "GP_Gen5_2"
    capacity = 2
    tier = "GeneralPurpose"
    family = "Gen5"
  }

  # Current Database backup use 5.51GB (2018/08/23)
  storage_profile {
    storage_mb = 10240
    backup_retention_days = 7
    geo_redundant_backup = "Enabled"
  }

  # Once the infrastructure has been deployed, the password should be manually
  # reset such that it can be utilized in Kubernetes/Puppet/etc
  administrator_login = "mysqladmin"
  administrator_login_password = "${random_id.prefix.hex}!Z3"
  version = "5.7"
  ssl_enforcement = "Enabled"
}

resource "azurerm_mysql_database" "confluence" {
  name                = "confluence"
  resource_group_name = "${azurerm_resource_group.confluence.name}"
  server_name         = "${azurerm_mysql_server.confluence.name}"
  charset             = "utf8"
  collation           = "utf8_bin"
}

# Allow connection from lettuce
resource "azurerm_mysql_firewall_rule" "confluence" {
  name                = "confluence"
  resource_group_name = "${azurerm_resource_group.confluence.name}"
  server_name         = "${azurerm_mysql_server.confluence.name}"
  start_ip_address    = "140.211.9.32"
  end_ip_address      = "140.211.9.32"
}

resource "azurerm_mysql_configuration" "confluence_character_set_server" {
  name                = "character_set_server"
  resource_group_name = "${azurerm_resource_group.confluence.name}"
  server_name         = "${azurerm_mysql_server.confluence.name}"
  value               = "UTF8"
}

# https://confluence.atlassian.com/confkb/confluence-fails-to-start-and-throws-mysql-session-isolation-level-repeatable-read-is-no-longer-supported-error-241568536.html
resource "azurerm_mysql_configuration" "confluence_tx_isolation" {
  name                = "tx_isolation"
  resource_group_name = "${azurerm_resource_group.confluence.name}"
  server_name         = "${azurerm_mysql_server.confluence.name}"
  value               = "READ-COMMITTED"
}

