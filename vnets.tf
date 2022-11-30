# The resources groups and virtual networks below are defined here:
# https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf

## Resource Groups
# Deprecation notice: not included in https://github.com/jenkins-infra/azure-net
data "azurerm_resource_group" "public_prod" {
  name = "prod-jenkins-public-prod"
}

# Deprecation notice: not included in https://github.com/jenkins-infra/azure-net
data "azurerm_resource_group" "private_prod" {
  name = "prod-jenkins-private-prod"
}

data "azurerm_resource_group" "prod_public" {
  name = "prod-jenkins-public"
}

data "azurerm_resource_group" "prod_private" {
  name = "prod-jenkins-private"
}

## Virtual Networks
# Deprecation notice: not included in https://github.com/jenkins-infra/azure-net
data "azurerm_virtual_network" "public_prod" {
  name                = "prod-jenkins-public-prod"
  resource_group_name = data.azurerm_resource_group.public_prod.name
}

# Deprecation notice: not included in https://github.com/jenkins-infra/azure-net
data "azurerm_virtual_network" "private_prod" {
  name                = "prod-jenkins-private-prod-vnet"
  resource_group_name = data.azurerm_resource_group.private_prod.name
}

# TODO: restore after azure-net vnets renaming
# data "azurerm_virtual_network" "prod_public" {
#   name                = "prod-jenkins-public-vnet"
#   resource_group_name = data.azurerm_resource_group.prod_public.name
# }

# data "azurerm_virtual_network" "prod_private" {
#   name                = "prod-jenkins-private-vnet"
#   resource_group_name = data.azurerm_resource_group.prod_private.name
# }

################################################################################
## SUB NETWORKS
################################################################################

# "pgsql-tier" subnet is reserved as "delegated" for the pgsql server on the public network
# Ref. https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking
resource "azurerm_subnet" "pgsql_tier" {
  name                 = "pgsql-tier"
  resource_group_name  = data.azurerm_resource_group.public_prod.name
  virtual_network_name = data.azurerm_virtual_network.public_prod.name
  address_prefixes     = ["10.0.3.0/24"]
  delegation {
    name = "pgsql"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "public_pgsql" {
  subnet_id                 = azurerm_subnet.pgsql_tier.id
  network_security_group_id = azurerm_network_security_group.public_pgsql_tier.id
}
