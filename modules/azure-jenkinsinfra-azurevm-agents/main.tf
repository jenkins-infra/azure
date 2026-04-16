####################################################################################
# Network resources defined in https://github.com/jenkins-infra/azure-net
####################################################################################
data "azurerm_resource_group" "ephemeral_agents_vnet" {
  name = var.ephemeral_agents_network_rg_name
}
data "azurerm_virtual_network" "ephemeral_agents" {
  name                = var.ephemeral_agents_network_name
  resource_group_name = data.azurerm_resource_group.ephemeral_agents_vnet.name
}
data "azurerm_subnet" "ephemeral_agents" {
  name                 = var.ephemeral_agents_subnet_name
  virtual_network_name = data.azurerm_virtual_network.ephemeral_agents.name
  resource_group_name  = data.azurerm_resource_group.ephemeral_agents_vnet.name
}

####################################################################################
## Network Security Group and rules
####################################################################################
### Ephemeral Agents
resource "azurerm_network_security_group" "ephemeral_agents" {
  name                = "${var.service_fqdn}-ephemeralagents"
  location            = data.azurerm_resource_group.ephemeral_agents_vnet.location
  resource_group_name = var.controller_rg_name
  tags                = var.default_tags
}
resource "azurerm_subnet_network_security_group_association" "ephemeral_agents" {
  subnet_id                 = data.azurerm_subnet.ephemeral_agents.id
  network_security_group_id = azurerm_network_security_group.ephemeral_agents.id
}
## Outbound Rules (different set of priorities than Inbound rules) ##
resource "azurerm_network_security_rule" "allow_outbound_hkp_udp_from_ephemeral_agents_subnet_to_internet" {
  name                    = "allow-outbound-hkp-udp-from-${var.service_short_stripped_name}_ephemeral_agents-to-internet"
  priority                = 4090
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Udp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ephemeral_agents.address_prefixes
  destination_port_ranges = [
    "11371", # HKP (OpenPGP KeyServer) - https://github.com/jenkins-infra/helpdesk/issues/3664
  ]
  destination_address_prefixes = local.external_service_ips["gpg_keyserver"]
  resource_group_name          = var.controller_rg_name
  network_security_group_name  = azurerm_network_security_group.ephemeral_agents.name
}
resource "azurerm_network_security_rule" "allow_outbound_hkp_tcp_from_ephemeral_agents_subnet_to_internet" {
  name                    = "allow-outbound-hkp-tcp-from-${var.service_short_stripped_name}_ephemeral_agents-to-internet"
  priority                = 4091
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ephemeral_agents.address_prefixes
  destination_port_ranges = [
    "11371", # HKP (OpenPGP KeyServer) - https://github.com/jenkins-infra/helpdesk/issues/3664
  ]
  destination_address_prefixes = local.external_service_ips["gpg_keyserver"]
  resource_group_name          = var.controller_rg_name
  network_security_group_name  = azurerm_network_security_group.ephemeral_agents.name
}
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_ephemeral_agents_to_internet" {
  name                    = "allow-outbound-ssh-from-${var.service_short_stripped_name}_ephemeral_agents-to-internet"
  priority                = 4092
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ephemeral_agents.address_prefixes
  destination_port_range  = "22"
  #Filter only for ipv4 ips
  destination_address_prefixes = [
    for ip in split(" ", local.github_destination_address_prefixes) : ip
    if can(cidrnetmask(ip))
  ]
  resource_group_name         = var.controller_rg_name
  network_security_group_name = azurerm_network_security_group.ephemeral_agents.name
}
resource "azurerm_network_security_rule" "allow_outbound_jenkins_from_ephemeral_agents_to_controller" {
  name                    = "allow-outbound-jenkins-from-${var.service_short_stripped_name}-agents"
  priority                = 4093
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ephemeral_agents.address_prefixes
  destination_port_ranges = [
    "80",    # HTTP
    "443",   # HTTPS
    "50000", # Direct TCP Inbound protocol
  ]
  destination_address_prefixes = compact(var.controller_ips)
  resource_group_name          = var.controller_rg_name
  network_security_group_name  = azurerm_network_security_group.ephemeral_agents.name
}
resource "azurerm_network_security_rule" "allow_outbound_http_from_ephemeral_agents_to_internet" {
  name                    = "allow-outbound-http-from-${var.service_short_stripped_name}_ephemeral_agents-to-internet"
  priority                = 4094
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ephemeral_agents.address_prefixes
  destination_port_ranges = [
    "80",  # HTTP
    "443", # HTTPS
  ]
  destination_address_prefix  = "Internet"
  resource_group_name         = var.controller_rg_name
  network_security_group_name = azurerm_network_security_group.ephemeral_agents.name
}
resource "azurerm_network_security_rule" "deny_all_outbound_from_ephemeral_agents_to_internet" {
  name                        = "deny-all-outbound-from-${var.service_short_stripped_name}_ephemeral_agents-to-internet"
  priority                    = 4095
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = data.azurerm_subnet.ephemeral_agents.address_prefixes
  destination_address_prefix  = "Internet"
  resource_group_name         = var.controller_rg_name
  network_security_group_name = azurerm_network_security_group.ephemeral_agents.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000.
resource "azurerm_network_security_rule" "deny_all_outbound_from_ephemeral_agents_to_vnet" {
  name                        = "deny-all-outbound-from-${var.service_short_stripped_name}_ephemeral_agents-to-vnet"
  priority                    = 4096 # Maximum value allowed by Azure API
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = data.azurerm_subnet.ephemeral_agents.address_prefixes
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = var.controller_rg_name
  network_security_group_name = azurerm_network_security_group.ephemeral_agents.name
}

## Inbound Rules (different set of priorities than Outbound rules) ##
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_privatevpn_to_ephemeral_agents" {
  name                        = "allow-inbound-ssh-from-privatevpn-to-${var.service_short_stripped_name}-ephemeral-agents"
  priority                    = 4085
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.jenkins_infra_ips.privatevpn_subnet
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = var.controller_rg_name
  network_security_group_name = azurerm_network_security_group.ephemeral_agents.name
}
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_controller_to_ephemeral_agents" {
  name                         = "allow-inbound-ssh-from-${var.service_short_stripped_name}-controller-to-ephemeral-agents"
  priority                     = 4090
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  source_address_prefixes      = var.controller_ips
  destination_port_range       = "22" # SSH
  destination_address_prefixes = data.azurerm_subnet.ephemeral_agents.address_prefixes
  resource_group_name          = var.controller_rg_name
  network_security_group_name  = azurerm_network_security_group.ephemeral_agents.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000
resource "azurerm_network_security_rule" "deny_all_inbound_from_vnet_to_ephemeral_agents" {
  name                         = "deny-all-inbound-from-vnet-to-${var.service_short_stripped_name}_ephemeral_agents"
  priority                     = 4096 # Maximum value allowed by the Azure Terraform Provider
  direction                    = "Inbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "*"
  destination_address_prefixes = data.azurerm_subnet.ephemeral_agents.address_prefixes
  resource_group_name          = var.controller_rg_name
  network_security_group_name  = azurerm_network_security_group.ephemeral_agents.name
}

####################################################################################
## Azure Active Directory Resources to allow controller spawning ephemeral agents
####################################################################################
resource "azurerm_role_assignment" "controller_contributor_in_ephemeral_agent_resourcegroup" {
  scope                = azurerm_resource_group.ephemeral_agents.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = var.controller_service_principal_id
}
resource "azurerm_role_assignment" "controller_io_manage_net_interfaces_subnet_ephemeral_agents" {
  scope                = data.azurerm_subnet.ephemeral_agents.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = var.controller_service_principal_id
}
resource "azurerm_role_assignment" "controller_network_contributor_in_ephemeral_agent_resourcegroup" {
  scope                = azurerm_resource_group.ephemeral_agents.id
  role_definition_name = "Network Contributor"
  principal_id         = var.controller_service_principal_id
}
resource "azurerm_role_assignment" "additional_identities_contributor_in_ephemeral_agent_resourcegroup" {
  count                = length(var.additional_identities)
  scope                = azurerm_resource_group.ephemeral_agents.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = var.additional_identities[count.index]
}
resource "azurerm_role_assignment" "additional_identities_io_manage_net_interfaces_subnet_ephemeral_agents" {
  count                = length(var.additional_identities)
  scope                = data.azurerm_subnet.ephemeral_agents.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = var.additional_identities[count.index]
}
resource "azurerm_role_assignment" "additional_identities_network_contributor_in_ephemeral_agent_resourcegroup" {
  count                = length(var.additional_identities)
  scope                = azurerm_resource_group.ephemeral_agents.id
  role_definition_name = "Network Contributor"
  principal_id         = var.additional_identities[count.index]
}

####################################################################################
## Azurerm Resources for the Ephemeral Agents (Azure VM Jenkins plugin)
####################################################################################
resource "azurerm_resource_group" "ephemeral_agents" {
  name     = var.custom_resourcegroup_name == "" ? "${var.service_short_stripped_name}-ephemeral-agents" : var.custom_resourcegroup_name
  location = data.azurerm_resource_group.ephemeral_agents_vnet.location
  tags     = var.default_tags
}
# Storage Account is required by the Azure-VM plugin to allow passing init scripts to VM during the boot phase
resource "azurerm_storage_account" "ephemeral_agents" {
  name                     = var.storage_account_name == "" ? "${replace(replace(var.service_fqdn, ".", ""), "-", "")}agents" : var.storage_account_name
  resource_group_name      = azurerm_resource_group.ephemeral_agents.name # must be the same RG as the ephemeral VMs
  location                 = data.azurerm_resource_group.ephemeral_agents_vnet.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # default value, needed for tfsec
  tags                     = var.default_tags
}
