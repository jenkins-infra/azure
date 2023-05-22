################################################################################
## Public Network
################################################################################
# TODO: remove after migration from prodpublick8s to publick8s is completed (ref: https://github.com/jenkins-infra/helpdesk/issues/3351)
resource "azurerm_network_security_group" "public_pgsql_tier" {
  name                = "public-network-pgsql-tier"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.public_prod.name
}

resource "azurerm_network_security_group" "data_pgsql_tier" {
  name                = "public-network-data-pgsql-tier"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.public.name
}
