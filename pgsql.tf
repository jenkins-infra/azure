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
  administrator_login    = local.public_pgsql_admin_login
  administrator_password = random_password.pgsql_admin_password.result
  sku_name               = "B_Standard_B1ms" # 1vCore / 2 Gb - https://docs.microsoft.com/en-us/azure/virtual-machines/sizes-b-series-burstable
  storage_mb             = "32768"
  version                = "13"
  zone                   = "1"
  private_dns_zone_id    = azurerm_private_dns_zone.public_pgsql.id
  delegated_subnet_id    = azurerm_subnet.pgsql_tier.id

  depends_on = [
    /**
    The network link from private pod is required to allow the provider "postgresql"
    to connect to this server from the private Jenkins agents where terraform runs
    (or through VPN tunnelling)
    **/
    azurerm_private_dns_zone_virtual_network_link.privatevnet_to_publicpgsql,
  ]
}

resource "azurerm_private_dns_zone" "public_pgsql" {
  name                = "public-pgsql.jenkins-infra.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.public_prod.name
}

# TODO: remove after migration from prodpublick8s to publick8s is completed (ref: https://github.com/jenkins-infra/helpdesk/issues/3351)
resource "azurerm_private_dns_zone_virtual_network_link" "publicvnet_to_publicpgsql" {
  name                  = "publicvnet-to-publicpgsql"
  resource_group_name   = data.azurerm_resource_group.public_prod.name
  private_dns_zone_name = azurerm_private_dns_zone.public_pgsql.name
  virtual_network_id    = data.azurerm_virtual_network.public_prod.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "publicpgsql_to_publicvnet" {
  name                  = "publicpgsql-to-publicvnet"
  resource_group_name   = data.azurerm_resource_group.public_prod.name
  private_dns_zone_name = azurerm_private_dns_zone.public_pgsql.name
  virtual_network_id    = data.azurerm_virtual_network.public.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "privatevnet_to_publicpgsql" {
  name                  = "privatevnet-to-publicpgsql"
  resource_group_name   = data.azurerm_resource_group.public_prod.name
  private_dns_zone_name = azurerm_private_dns_zone.public_pgsql.name
  virtual_network_id    = data.azurerm_virtual_network.private_prod.id
}
