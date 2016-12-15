#
# This terraform plan defines the resources necessary to provision the Network
# Security Groups for all our Virtual Networks (defined in vnets.tf)

## NETWORK SECURITY GROUPS
################################################################################
# Allow pretty much any and all traffic into the development DMZ. Wild west!
# This will make management a bit easier since new services will simply have
# their ports available by default
resource "azurerm_network_security_group" "development_dmz" {
  name                = "dev-network-dmz"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.development.name}"

  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Allow HTTP(s) by default to anything in the Public Production application
# tier. It is presumed that applications are generally webservices
resource "azurerm_network_security_group" "public_app_tier" {
  name                = "public-network-apptier"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.public_prod.name}"

  security_rule {
    name                       = "allow-http-inbound"
    priority                   = 100
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "tcp"
    source_port_range          = "80"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 101
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "tcp"
    source_port_range          = "443"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Always allow SSH from machines in our Private Production network
  security_rule {
    name                       = "allow-private-ssh"
    priority                   = 4000
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "tcp"
    source_port_range          = "22"
    destination_port_range     = "*"
    source_address_prefix      = "${element(azurerm_virtual_network.private_prod.address_space, 0)}"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-puppet-outbound"
    priority                   = 2100
    direction                  = "outbound"
    access                     = "allow"
    protocol                   = "tcp"
    source_port_range          = "${var.puppet_master_port}"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "${element(azurerm_virtual_network.private_prod.address_space, 0)}"
  }

  security_rule {
    name                       = "deny-all-else"
    priority                   = 4096
    direction                  = "inbound"
    access                     = "deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# NOTE: Currently empty to enable us to add security rules to this NSG at a
# later date.
resource "azurerm_network_security_group" "public_data_tier" {
  name                = "public-network-datatier"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.public_prod.name}"

  # Always allow SSH from machines in our Private Production network
  security_rule {
    name                       = "allow-private-ssh"
    priority                   = 4000
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "tcp"
    source_port_range          = "22"
    destination_port_range     = "*"
    source_address_prefix      = "${element(azurerm_virtual_network.private_prod.address_space, 0)}"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-puppet-outbound"
    priority                   = 2100
    direction                  = "outbound"
    access                     = "allow"
    protocol                   = "tcp"
    source_port_range          = "${var.puppet_master_port}"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "${element(azurerm_virtual_network.private_prod.address_space, 0)}"
  }

  security_rule {
    name                       = "deny-all-else"
    priority                   = 4096
    direction                  = "inbound"
    access                     = "deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# NOTE: Currently empty to enable us to add security rules to this NSG at a
# later date.
resource "azurerm_network_security_group" "public_dmz_tier" {
  name                = "public-network-dmztier"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.public_prod.name}"

  # Always allow SSH from machines in our Private Production network
  security_rule {
    name                       = "allow-private-ssh"
    priority                   = 4000
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "tcp"
    source_port_range          = "22"
    destination_port_range     = "*"
    source_address_prefix      = "${element(azurerm_virtual_network.private_prod.address_space, 0)}"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-else"
    priority                   = 4096
    direction                  = "inbound"
    access                     = "deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "private_mgmt_tier" {
  name                = "private-network-mgmt-tier"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.private_prod.name}"

  security_rule {
    name                       = "deny-all-internet"
    priority                   = 100
    direction                  = "inbound"
    access                     = "deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "INTERNET"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 200
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "TCP"
    source_port_range          = "443"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-puppet-inbound"
    priority                   = 300
    direction                  = "inbound"
    access                     = "allow"
    protocol                   = "TCP"
    source_port_range          = "${var.puppet_master_port}"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_security_group" "private_dmz_tier" {
  name                = "private-network-dmz-tier"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.private_prod.name}"
}
################################################################################
