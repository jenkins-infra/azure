# NOTE: managing DB resources requires routes to database (private endpoints and private DNSes):
# * Either:
# ** VPN access is required with routing to the database subnets set up to your user,
# ** OR running terraform in a subnet with a private endpoint access/routing to the DB subnet
# * Also, as there are no public DNS, either:
# ** Set up your local `/etc/hosts` (check the `providers.tf` for details),
# ** OR have your subnet set up to use the private DNS records
######
# Dedicated subnet is reserved as "delegated" for the mysql server on the public network
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
  version                      = "8.0.21"
  zone                         = "1"
  geo_redundant_backup_enabled = false
  private_dns_zone_id          = azurerm_private_dns_zone.public_db_mysql.id
  delegated_subnet_id          = data.azurerm_subnet.public_db_vnet_mysql_tier.id

  depends_on = [
    /**
    The network link from private pod is required to allow the provider "mysql"
    to connect to this server from the private Jenkins agents where terraform runs
    (or through VPN tunnelling)
    **/
    azurerm_private_dns_zone_virtual_network_link.public_db_mysql["private-vnet"],
    azurerm_private_dns_zone_virtual_network_link.public_db_mysql["infracijenkinsio-sponsorship-vnet"],
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
    "public-vnet"                       = data.azurerm_virtual_network.public.id,
    "publicdb-vnet"                     = data.azurerm_virtual_network.public_db.id,
    "private-vnet"                      = data.azurerm_virtual_network.private.id,
    "infracijenkinsio-sponsorship-vnet" = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.id,
  }
  name                  = "${each.key}-to-publicdbmysql"
  resource_group_name   = data.azurerm_resource_group.public.name
  private_dns_zone_name = azurerm_private_dns_zone.public_db_mysql.name
  virtual_network_id    = each.value
}
