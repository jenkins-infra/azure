# Reference to the PostgreSQL/MySql dedicated network external resources
# ALREADY LOADED IN postgres-public-db.tf
# data "azurerm_virtual_network" "public_db"

# Dedicated subnet is reserved as "delegated" for the mysql server (same as the postgres) on the public network
# not specificaly needed as per the mysql flexible server documentation :
# Ref. https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking
# but seem adequate to use Private access (VNet integration) https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking#choose-a-networking-option
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_subnet" "public_db_vnet_mysql_tier" {
  name                 = "${data.azurerm_virtual_network.public_db.name}-mysql-tier"
  virtual_network_name = data.azurerm_virtual_network.public_db.name
  resource_group_name  = data.azurerm_resource_group.public.name
}
resource "azurerm_network_security_group" "db_mysql_tier" {
  name                = "${data.azurerm_virtual_network.public_db.name}-mysql"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.public.name
}
resource "azurerm_subnet_network_security_group_association" "db_mysql_tier" {
  subnet_id                 = data.azurerm_subnet.public_db_vnet_mysql_tier.id
  network_security_group_id = azurerm_network_security_group.db_mysql_tier.id
}
# Used by 'local.public_db_mysql_admin_login' (which is itself needed by the mysql provider)
resource "random_password" "public_db_mysql_admin_login" {
  length  = 14
  special = false
  upper   = false
}
# Generate random value for the login password see https://learn.microsoft.com/en-us/azure/mysql/flexible-server/quickstart-create-terraform?tabs=azure-cli#implement-the-terraform-code
resource "random_password" "public_db_mysql_admin_password" {
  length           = 8
  lower            = true
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  numeric          = true
  override_special = "_"
  special          = true
  upper            = true
}

# Manages the MySQL Flexible Server https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mysql_flexible_server
resource "azurerm_mysql_flexible_server" "public_db_mysql" {
  name                         = "public-db-mysql"
  resource_group_name          = data.azurerm_resource_group.public.name
  location                     = var.location
  administrator_login          = local.public_db_mysql_admin_login
  administrator_password       = random_password.public_db_mysql_admin_password.result
  sku_name                     = "B_Standard_B1ms" # 1vCore / 2 Gb - https://docs.microsoft.com/en-us/azure/virtual-machines/sizes-b-series-burstable
  version                      = "8.0.21"          # TODO can be 5.7 as per https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mysql_flexible_server
  zone                         = "1"
  geo_redundant_backup_enabled = false #TODO  Changing this forces a new MySQL Flexible Server to be created
  private_dns_zone_id          = azurerm_private_dns_zone.public_db_mysql.id
  delegated_subnet_id          = data.azurerm_subnet.public_db_vnet_mysql_tier.id

  high_availability { # TODO  Changing this forces a new MySQL Flexible Server to be recreated
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  depends_on = [
    /**
    The network link from private pod is required to allow the provider "mysql"
    to connect to this server from the private Jenkins agents where terraform runs
    (or through VPN tunnelling)
    **/
    azurerm_private_dns_zone_virtual_network_link.public_db_mysql["private-vnet"],
  ]

}

# Enables you to manage Private DNS zones within Azure DNS
resource "azurerm_private_dns_zone" "public_db_mysql" {
  name                = "public-db-mysql.jenkins-infra.mysql.database.azure.com"
  resource_group_name = data.azurerm_resource_group.public.name
}

# Enables you to manage Private DNS zone Virtual Network Links
resource "azurerm_private_dns_zone_virtual_network_link" "public_db_mysql" {
  for_each = {
    "public-vnet"   = data.azurerm_virtual_network.public.id,
    "publicdb-vnet" = data.azurerm_virtual_network.public_db.id,
    "private-vnet"  = data.azurerm_virtual_network.private.id
  }
  name                  = "${each.key}-to-publicdbmysql"
  resource_group_name   = data.azurerm_resource_group.public.name
  private_dns_zone_name = azurerm_private_dns_zone.public_db_mysql.name
  virtual_network_id    = each.value
}
