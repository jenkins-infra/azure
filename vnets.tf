# The resources groups and virtual networks below are defined here:
# https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf

## Resource Groups
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_resource_group" "public" {
  name = "public"
}
data "azurerm_resource_group" "private" {
  name = "private"
}

## Virtual Networks
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_virtual_network" "public" {
  name                = "${data.azurerm_resource_group.public.name}-vnet"
  resource_group_name = data.azurerm_resource_group.public.name
}
data "azurerm_virtual_network" "private" {
  name                = "${data.azurerm_resource_group.private.name}-vnet"
  resource_group_name = data.azurerm_resource_group.private.name
}
# Reference to the PostgreSQL/MySql dedicated network external resources
data "azurerm_virtual_network" "public_db" {
  name                = "${data.azurerm_resource_group.public.name}-db-vnet"
  resource_group_name = data.azurerm_resource_group.public.name
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
