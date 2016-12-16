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
resource "azurerm_resource_group" "public_prod" {
    name     = "${var.prefix}-jenkins-public-prod"
    location = "${var.location}"
}
resource "azurerm_resource_group" "private_prod" {
    name     = "${var.prefix}-jenkins-private-prod"
    location = "${var.location}"
}
resource "azurerm_resource_group" "development" {
    name     = "${var.prefix}-jenkins-development"
    location = "${var.location}"
}
################################################################################


## VIRTUAL NETWORKS
################################################################################
resource "azurerm_virtual_network" "public_prod" {
  name                = "${var.prefix}-jenkins-public-prod"
  resource_group_name = "${azurerm_resource_group.public_prod.name}"
  address_space       = ["10.0.0.0/16"]
  location            = "${var.location}"

  # "app-tier" hosts should expect to be accessible from the public internet
  subnet {
    name           = "app-tier"
    address_prefix = "10.0.1.0/24"
    security_group = "${azurerm_network_security_group.public_app_tier.id}"
  }

  # The "data-tier" subnet is for data services which we might choose to run
  # ourselves that shouldn't have public IP addresses but accessible from within
  # the Public Production network
  subnet {
    name           = "data-tier"
    address_prefix = "10.0.2.0/24"
    security_group = "${azurerm_network_security_group.public_data_tier.id}"
  }

  # The "dmz-tier" subnet is intended for resources which need to be
  # provisioned in the Public Production network but don't need to be
  # accessible from the public internet. Such as dynamically provisioned VMs for
  # Jenkins masters, or other untrusted workloads which should be in the Public
  # Production VNet
  subnet {
    name           = "dmz-tier"
    address_prefix = "10.0.99.0/24"
    security_group = "${azurerm_network_security_group.public_dmz_tier.id}"
  }
}

# The Private Production VNet is where all management and highly classified
# resources should be provisioned. It should never have its resources exposed
# to the public internet but is peered with Public Production
resource "azurerm_virtual_network" "private_prod" {
  name                = "${var.prefix}-jenkins-private-prod"
  resource_group_name = "${azurerm_resource_group.private_prod.name}"
  address_space       = ["10.1.0.0/16"]
  location            = "${var.location}"

  subnet {
    name           = "management-tier"
    address_prefix = "10.1.1.0/24"
    security_group = "${azurerm_network_security_group.private_mgmt_tier.id}"
  }

  subnet {
    name           = "data-tier"
    address_prefix = "10.1.2.0/24"
    security_group = "${azurerm_network_security_group.private_dmz_tier.id}"
  }
}

# Peer the Public and Private Production networks, using the Private Production
# resource group for holding the VNet Peer
resource "azurerm_virtual_network_peering" "pub_to_priv_peer" {
    name                      = "${var.prefix}-public-to-private-peer"
    resource_group_name       = "${azurerm_resource_group.private_prod.name}"
    virtual_network_name      = "${azurerm_virtual_network.private_prod.name}"
    remote_virtual_network_id = "${azurerm_virtual_network.public_prod.id}"
}

# The development VNet should be largely considered entirely on its own and
# almost like the wild-west. Nothing sensitive should live there, nor should it
# be peered with the other networks
resource "azurerm_virtual_network" "development" {
  name                = "${var.prefix}-jenkins-development"
  resource_group_name = "${azurerm_resource_group.development.name}"
  address_space       = ["10.2.0.0/16"]
  location            = "${var.location}"

  # Pretty much everything in the development VNet should be considered
  # untrusted and almost like the wild west
  subnet {
    name           = "dmz-tier"
    address_prefix = "10.2.99.0/24"
    security_group = "${azurerm_network_security_group.development_dmz.id}"
  }
}
################################################################################
