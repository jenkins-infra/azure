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

resource "azurerm_resource_group" "public_prod" {
    name     = "${var.prefix}-jenkins-public-prod"
    location = "${var.location}"
}
resource "azurerm_virtual_network" "public_prod" {
  name                = "${var.prefix}-jenkins-public-prod"
  resource_group_name = "${azurerm_resource_group.public_prod.name}"
  address_space       = ["10.0.0.0/16"]
  location            = "${var.location}"

  # "app-tier" hosts should expect to be accessible from the public internet
  subnet {
    name           = "app-tier"
    address_prefix = "10.0.1.0/24"
  }

  # The "data-tier" subnet is for data services which we might choose to run
  # ourselves that shouldn't have public IP addresses but accessible from within
  # the Public Production network
  subnet {
    name           = "data-tier"
    address_prefix = "10.0.2.0/24"
  }

  # The "dmz-tier" subnet is intended for resources which need to be
  # provisioned in the Public Production network but don't need to be
  # accessible from the public internet. Such as dynamically provisioned VMs for
  # Jenkins masters, or other untrusted workloads which should be in the Public
  # Production VNet
  subnet {
    name           = "dmz-tier"
    address_prefix = "10.0.99.0/24"
  }
}

# The Private Production VNet is where all management and highly classified
# resources should be provisioned. It should never have its resources exposed
# to the public internet but is peered with Public Production
resource "azurerm_resource_group" "private_prod" {
    name     = "${var.prefix}-jenkins-private-prod"
    location = "${var.location}"
}
resource "azurerm_virtual_network" "private_prod" {
  name                = "${var.prefix}-jenkins-private-prod"
  resource_group_name = "${azurerm_resource_group.private_prod.name}"
  address_space       = ["10.1.0.0/16"]
  location            = "${var.location}"

  subnet {
    name           = "management-tier"
    address_prefix = "10.1.1.0/24"
  }

  subnet {
    name           = "data-tier"
    address_prefix = "10.1.2.0/24"
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

# Traffic should, in essence be unidirectional from Private to Public
# Production VNets. This means hosts inside of Public Production should not be
# able to access resources in Private Production unless there has been an
# explicit Network Security Group (NSG) rule provided for that (for example,
# allowing access to LDAPS or Puppet's agent channel)
resource "azurerm_network_security_group" "pub_to_priv_nsg" {
    name                = "${var.prefix}-public-to-private-nsg"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.private_prod.name}"

    security_rule {
        name                       = "priv-to-public-prod"
        priority                   = 100
        direction                  = "inbound"
        access                     = "allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "${element(azurerm_virtual_network.private_prod.address_space, 0)}"
        destination_address_prefix = "${element(azurerm_virtual_network.public_prod.address_space, 0)}"
    }

    security_rule {
        name                       = "public-to-priv-prod"
        priority                   = 200
        direction                  = "inbound"
        access                     = "deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "${element(azurerm_virtual_network.public_prod.address_space, 0)}"
        destination_address_prefix = "${element(azurerm_virtual_network.private_prod.address_space, 0)}"
    }
}


################################################################################

# The development VNet should be largely considered entirely on its own and
# almost like the wild-west. Nothing sensitive should live there, nor should it
# be peered with the other networks
resource "azurerm_resource_group" "development" {
    name     = "${var.prefix}-jenkins-development"
    location = "${var.location}"
}

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
  }
}
