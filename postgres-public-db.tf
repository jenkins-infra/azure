# Dedicated subnet is reserved as "delegated" for the pgsql server on the public network
# Ref. https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_subnet" "public_db_vnet_postgres_tier" {
  name                 = "${data.azurerm_virtual_network.public_db.name}-postgres-tier"
  virtual_network_name = data.azurerm_virtual_network.public_db.name
  resource_group_name  = data.azurerm_resource_group.public.name
}
resource "azurerm_network_security_group" "db_pgsql_tier" {
  name                = "${data.azurerm_virtual_network.public_db.name}-postgres"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.public.name
}
resource "azurerm_subnet_network_security_group_association" "db_pgsql_tier" {
  subnet_id                 = data.azurerm_subnet.public_db_vnet_postgres_tier.id
  network_security_group_id = azurerm_network_security_group.db_pgsql_tier.id
}
# Used by 'local.public_db_pgsql_admin_login' (which is itself needed by the postgres provider)
resource "random_password" "public_db_pgsql_admin_login" {
  length  = 14
  special = false
  upper   = false
}
resource "random_password" "public_db_pgsql_admin_password" {
  length = 24
}
resource "azurerm_postgresql_flexible_server" "public_db" {
  name                          = "public-db"
  resource_group_name           = data.azurerm_resource_group.public.name
  location                      = var.location
  public_network_access_enabled = false
  administrator_login           = local.public_db_pgsql_admin_login
  administrator_password        = random_password.public_db_pgsql_admin_password.result
  sku_name                      = "B_Standard_B1ms" # 1vCore / 2 Gb - https://docs.microsoft.com/en-us/azure/virtual-machines/sizes-b-series-burstable
  storage_mb                    = "131072"
  version                       = "13"
  zone                          = "1"
  private_dns_zone_id           = azurerm_private_dns_zone.public_db_pgsql.id
  delegated_subnet_id           = data.azurerm_subnet.public_db_vnet_postgres_tier.id

  depends_on = [
    /**
    The network link from private pod is required to allow the provider "postgresql"
    to connect to this server from the private Jenkins agents where terraform runs
    (or through VPN tunnelling)
    **/
    azurerm_private_dns_zone_virtual_network_link.public_db_pgsql["private-vnet"],
  ]
}
resource "azurerm_private_dns_zone" "public_db_pgsql" {
  name                = "public-db-pgsql.jenkins-infra.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.public.name
}
resource "azurerm_private_dns_zone_virtual_network_link" "public_db_pgsql" {
  for_each = {
    "public-vnet"   = data.azurerm_virtual_network.public.id,
    "publicdb-vnet" = data.azurerm_virtual_network.public_db.id,
    "private-vnet"  = data.azurerm_virtual_network.private.id
  }
  name                  = "${each.key}-to-publicdbpgsql"
  resource_group_name   = data.azurerm_resource_group.public.name
  private_dns_zone_name = azurerm_private_dns_zone.public_db_pgsql.name
  virtual_network_id    = each.value
}
