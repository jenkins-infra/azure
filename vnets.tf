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

# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_resource_group" "public" {
  name = "public"
}
data "azurerm_resource_group" "private" {
  name = "private"
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

# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_virtual_network" "public" {
  name                = "${data.azurerm_resource_group.public.name}-vnet"
  resource_group_name = data.azurerm_resource_group.public.name
}
data "azurerm_virtual_network" "private" {
  name                = "${data.azurerm_resource_group.private.name}-vnet"
  resource_group_name = data.azurerm_resource_group.private.name
}

################################################################################
## SUB NETWORKS
################################################################################

# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vpn.tf
data "azurerm_subnet" "private_vnet_data_tier" {
  name                 = "${data.azurerm_virtual_network.private.name}-data-tier"
  virtual_network_name = data.azurerm_virtual_network.private.name
  resource_group_name  = data.azurerm_resource_group.private.name
}

# "pgsql-tier" subnet is reserved as "delegated" for the pgsql server on the public network
# Ref. https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking
# TODO: remove after migration from prodpublick8s to publick8s is completed (ref: https://github.com/jenkins-infra/helpdesk/issues/3351)
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

# TODO: remove after migration from prodpublick8s to publick8s is completed (ref: https://github.com/jenkins-infra/helpdesk/issues/3351)
resource "azurerm_subnet_network_security_group_association" "public_pgsql" {
  subnet_id                 = azurerm_subnet.pgsql_tier.id
  network_security_group_id = azurerm_network_security_group.public_pgsql_tier.id
}

# Dedicated subnet is reserved as "delegated" for the pgsql server on the public network
# Ref. https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_subnet" "public_vnet_postgres_tier" {
  name                 = "${data.azurerm_virtual_network.public.name}-postgres-tier"
  virtual_network_name = data.azurerm_virtual_network.public.name
  resource_group_name  = data.azurerm_resource_group.public.name
}

resource "azurerm_subnet_network_security_group_association" "data_pgsql" {
  subnet_id                 = data.azurerm_subnet.public_vnet_postgres_tier.id
  network_security_group_id = azurerm_network_security_group.data_pgsql_tier.id
}
