#
# This terraform plan defines the resources necessary to provision the Virtual
# Networks in Azure according to IEP-002:
#   <https://github.com/jenkins-infra/iep/tree/master/iep-002>
#
#                        +---------------------+
#                        |                     |
#      +---------------> |  Public Production  <-------+
#      |                 |                     |       |
#      |                 +---------------------+     VNet Peering
#      |                                               |
#      |                                 +-------------v--------+
#                        +-------------+ |                      |
# The Internet --------> + VPN Gateway |-|  Private Production  |
#                        +-------------+ |                      |
#      |                                 +----------------------+
#      |
#      |                 +----------------+
#      |                 |                |
#      +---------------> |   Development  |
#                        |                |
#                        +----------------+
#
## RESOURCE GROUPS
################################################################################
data "azurerm_resource_group" "public_prod" {
  name = "prod-jenkins-public-prod"
}

data "azurerm_resource_group" "private_prod" {
  name = "prod-jenkins-private-prod"
}

################################################################################
## VIRTUAL NETWORKS
################################################################################
data "azurerm_virtual_network" "public_prod" {
  name                = "prod-jenkins-public-prod"
  resource_group_name = data.azurerm_resource_group.public_prod.name
}

data "azurerm_virtual_network" "private_prod" {
  name                = "prod-jenkins-private-prod-vnet"
  resource_group_name = data.azurerm_resource_group.private_prod.name
}

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
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "public_pgsql" {
  subnet_id                 = azurerm_subnet.pgsql_tier.id
  network_security_group_id = azurerm_network_security_group.public_pgsql_tier.id
}
