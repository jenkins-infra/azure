################################################################################
## Public Network
################################################################################
resource "azurerm_network_security_group" "public_pgsql_tier" {
  name                = "public-network-pgsql-tier"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.public_prod.name
}
