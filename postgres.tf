resource "random_password" "data_pgsql_admin_login" {
  length  = 14
  special = false
  upper   = false
}

resource "random_password" "data_pgsql_admin_password" {
  length = 24
}

resource "azurerm_private_dns_zone" "data_pgsql" {
  name                = "data-pgsql.jenkins-infra.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.public.name
}

resource "azurerm_postgresql_flexible_server" "data" {
  name                   = "data"
  resource_group_name    = data.azurerm_resource_group.public.name
  location               = var.location
  administrator_login    = local.data_pgsql_admin_login
  administrator_password = random_password.data_pgsql_admin_password.result
  sku_name               = "B_Standard_B1ms" # 1vCore / 2 Gb - https://docs.microsoft.com/en-us/azure/virtual-machines/sizes-b-series-burstable
  storage_mb             = "32768"
  version                = "13"
  zone                   = "1"
  private_dns_zone_id    = azurerm_private_dns_zone.data_pgsql.id
  delegated_subnet_id    = data.azurerm_subnet.public_vnet_postgres_tier.id

  depends_on = [
    /**
    The network link from private pod is required to allow the provider "postgresql"
    to connect to this server from the private Jenkins agents where terraform runs
    (or through VPN tunnelling)
    **/
    azurerm_private_dns_zone_virtual_network_link.privatevnet_to_datapgsql,
  ]
}

resource "azurerm_private_dns_zone" "data_pgsql" {
  name                = "data-pgsql.jenkins-infra.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.public.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "publicvnet_to_datapgsql" {
  name                  = "publicvnet-to-datapgsql"
  resource_group_name   = data.azurerm_resource_group.public.name
  private_dns_zone_name = azurerm_private_dns_zone.data_pgsql.name
  virtual_network_id    = data.azurerm_virtual_network.public.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "privatevnet_to_datapgsql" {
  name                  = "privatevnet-to-datapgsql"
  resource_group_name   = data.azurerm_resource_group.public.name
  private_dns_zone_name = azurerm_private_dns_zone.data_pgsql.name
  virtual_network_id    = data.azurerm_virtual_network.private.id
}
