# Defined in https://github.com/jenkins-infra/azure-net/blob/d30a37c27b649aebd158ecb5d631ff8d7f1bab4e/vnets.tf#L175-L183
data "azurerm_subnet" "ci_jenkins_io_controller" {
  name                 = "${data.azurerm_virtual_network.public.name}-ci_jenkins_io_controller"
  virtual_network_name = data.azurerm_virtual_network.public.name
  resource_group_name  = data.azurerm_resource_group.public.name
}

####################################################################################
## Resources for the Controller VM
####################################################################################
module "ci_jenkins_io" {
  source = "./.shared-tools/terraform/modules/azure-jenkins-controller"

  service_fqdn                 = "ci.jenkins.io"
  location                     = data.azurerm_virtual_network.public.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKvZ23dkvhjSU0Gxl5+mKcBOwmR7gqJDYeA1/Xzl3otV4CtC5te5Vx7YnNEFDXD6BsNkFaliXa34yE37WMdWl+exIURBMhBLmOPxEP/cWA5ZbXP//78ejZsxawBpBJy27uQhdcR0zVoMJc8Q9ShYl5YT/Tq1UcPq2wTNFvnrBJL1FrpGT+6l46BTHI+Wpso8BK64LsfX3hKnJEGuHSM0GAcYQSpXAeGS9zObKyZpk3of/Qw/2sVilIOAgNODbwqyWgEBTjMUln71Mjlt1hsEkv3K/VdvpFNF8VNq5k94VX6Rvg5FQBRL5IrlkuNwGWcBbl8Ydqk4wrD3b/PrtuLBEUsqbNhLnlEvFcjak+u2kzCov73csN/oylR0Tkr2y9x2HfZgDJVtvKjkkc4QERo7AqlTuy1whGfDYsioeabVLjZ9ahPjakv9qwcBrEEF+pAya7Q3AgNFVSdPgLDEwEO8GUHaxAjtyXXv9+yPdoDGmG3Pfn3KqM6UZjHCxne3Dr5ZE="
  dns_zone_name                = data.azurerm_dns_zone.jenkinsio.name
  dns_resourcegroup_name       = data.azurerm_resource_group.proddns_jenkinsio.name
  controller_subnet_id         = data.azurerm_subnet.ci_jenkins_io_controller.id
  controller_os_disk_size_gb   = 64
  controller_data_disk_size_gb = 512
  controller_vm_size           = "Standard_D8as_v5"
  is_public                    = true
  default_tags                 = local.default_tags
}
## Service DNS records
resource "azurerm_dns_cname_record" "ci_jenkins_io" {
  name                = trimsuffix(trimsuffix(module.ci_jenkins_io.service_fqdn, data.azurerm_dns_zone.jenkinsio.name), ".")
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = module.ci_jenkins_io.controller_public_fqdn
  tags                = local.default_tags
}
resource "azurerm_dns_cname_record" "assets_ci_jenkins_io" {
  name                = "assets.${azurerm_dns_cname_record.ci_jenkins_io.name}"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = module.ci_jenkins_io.controller_public_fqdn
  tags                = local.default_tags
}
####################################################################################
## Network Security Group and rules
####################################################################################
resource "azurerm_network_security_group" "ci_jenkins_io_controller" {
  name                = module.ci_jenkins_io.service_fqdn
  location            = data.azurerm_virtual_network.public.location
  resource_group_name = module.ci_jenkins_io.controller_resourcegroup_name
  tags                = local.default_tags
}
resource "azurerm_subnet_network_security_group_association" "ci_jenkins_io" {
  subnet_id                 = data.azurerm_subnet.ci_jenkins_io_controller.id
  network_security_group_id = azurerm_network_security_group.ci_jenkins_io_controller.id
}
## Outbound Rules (different set of priorities than Inbound rules) ##
# Ignore the rule as it does not detect the IP restriction to only ldap.jenkins.io"s host
#tfsec:ignore:azure-network-no-public-egress
resource "azurerm_network_security_rule" "allow_outbound_ldap_from_ci_controller_to_jenkinsldap" {
  name                        = "allow-outbound-ldap-from-ci-controller-to-jenkinsldap"
  priority                    = 4086
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = module.ci_jenkins_io.controller_private_ipv4
  destination_port_range      = "636" # LDAP over TLS
  destination_address_prefix  = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
# Ignore the rule as it does not detect the IP restriction to only puppet.jenkins.io"s host
#tfsec:ignore:azure-network-no-public-egress
resource "azurerm_network_security_rule" "allow_outbound_puppet_from_ci_controller_to_puppetmaster" {
  name                        = "allow-outbound-puppet-from-ci-controller-subnet-to-puppetmaster"
  priority                    = 4087
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = module.ci_jenkins_io.controller_private_ipv4
  destination_port_range      = "8140" # Puppet over TLS
  destination_address_prefix  = azurerm_public_ip.puppet_jenkins_io.ip_address
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
# Ignore the rule as it does not detect the IP restriction to only puppet.jenkins.io"s host
#tfsec:ignore:azure-network-no-public-egress
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_ci_controller_to_s390x" {
  name                        = "allow-outbound-ssh-from-ci-controller-to-s390x"
  priority                    = 4088
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = module.ci_jenkins_io.controller_private_ipv4
  destination_port_ranges     = ["22"]
  destination_address_prefix  = local.external_services["s390x.${data.azurerm_dns_zone.jenkinsio.name}"]
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
resource "azurerm_network_security_rule" "allow_outbound_http_from_ci_controller_to_internet" {
  name                        = "allow-outbound-http-from-ci-controller-to-internet"
  priority                    = 4089
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = module.ci_jenkins_io.controller_private_ipv4
  destination_port_ranges     = ["80", "443"]
  destination_address_prefix  = "Internet"
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000.
resource "azurerm_network_security_rule" "deny_all_outbound_from_ci_controller_subnet" {
  name                        = "deny-all-outbound-from-ci-controller-subnet"
  priority                    = 4096 # Maximum value allowed by the provider
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
## Inbound Rules (different set of priorities than Outbound rules) ##
#tfsec:ignore:azure-network-no-public-ingress
resource "azurerm_network_security_rule" "allow_inbound_web_from_everywhere_to_ci_controller" {
  name                  = "allow-inbound-web-from-everywhere-to-ci-controller"
  priority              = 4080
  direction             = "Inbound"
  access                = "Allow"
  protocol              = "Tcp"
  source_port_range     = "*"
  source_address_prefix = "*"
  destination_port_ranges = [
    "80",  # HTTP (for redirections to HTTPS)
    "443", # HTTPS
  ]
  destination_address_prefixes = [
    module.ci_jenkins_io.controller_private_ipv4,
    module.ci_jenkins_io.controller_public_ipv4,
  ]
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
#tfsec:ignore:azure-network-no-public-ingress
resource "azurerm_network_security_rule" "allow_inbound_jenkins_usage_from_everywhere_to_ci_controller" {
  name                  = "allow-inbound-jenkins-usage-from-everywhere-to-ci-controller"
  priority              = 4090
  direction             = "Inbound"
  access                = "Allow"
  protocol              = "Tcp"
  source_port_range     = "*"
  source_address_prefix = "*"
  destination_port_ranges = [
    "443",   # HTTPS for websocket agents
    "50000", # Direct TCP Inbound protocol
  ]
  destination_address_prefixes = [
    module.ci_jenkins_io.controller_private_ipv4,
    module.ci_jenkins_io.controller_public_ipv4,
  ]
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_privatevpn_to_ci_controller" {
  name                        = "allow-inbound-ssh-from-privatevpn-to-ci-controller"
  priority                    = 4094
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  destination_address_prefix  = module.ci_jenkins_io.controller_private_ipv4
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000
# Please note that Azure NSG default to "deny all inbound from Internet"
resource "azurerm_network_security_rule" "deny_all_inbound_from_vnet_to_ci_controller" {
  name                        = "deny-all-inbound-from-vnet-to-ci-controller"
  priority                    = 4096 # Maximum value allowed by the Azure Terraform Provider
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = module.ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_controller.name
}

####################################################################################
## Resources for the Ephemeral Agents
####################################################################################
resource "azurerm_resource_group" "ci_jenkins_io_ephemeral_agents" {
  name     = "ci-jenkins-io-ephemeral-agents"
  location = data.azurerm_virtual_network.public.location
  tags     = local.default_tags
}
data "azurerm_subnet" "ci_jenkins_io_ephemeral_agents" {
  name                 = "${data.azurerm_virtual_network.public.name}-ci_jenkins_io_agents"
  virtual_network_name = data.azurerm_virtual_network.public.name
  resource_group_name  = data.azurerm_resource_group.public.name
}
resource "azurerm_network_security_group" "ci_jenkins_io_ephemeral_agents" {
  name                = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.name
  location            = data.azurerm_resource_group.public.location
  resource_group_name = data.azurerm_resource_group.public.name
  tags                = local.default_tags
}
resource "azurerm_subnet_network_security_group_association" "ci_jenkins_io_ephemeral_agents" {
  subnet_id                 = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.id
  network_security_group_id = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.id
}
## Outbound Rules (different set of priorities than Inbound rules) ##
#tfsec:ignore:azure-network-no-public-egress
resource "azurerm_network_security_rule" "allow_outbound_hkp_udp_from_ci_jenkins_io_ephemeral_agents_subnet_to_internet" {
  name                    = "allow-outbound-hkp-udp-from-ci_jenkins_io_ephemeral_agents-subnet-to-internet"
  priority                = 4090
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Udp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_port_ranges = [
    "11371", # HKP (OpenPGP KeyServer) - https://github.com/jenkins-infra/helpdesk/issues/3664
  ]
  destination_address_prefixes = local.gpg_keyserver_ips["keyserver.ubuntu.com"]
  resource_group_name          = data.azurerm_resource_group.public.name
  network_security_group_name  = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
#tfsec:ignore:azure-network-no-public-egress
resource "azurerm_network_security_rule" "allow_outbound_hkp_tcp_from_ci_jenkins_io_ephemeral_agents_subnet_to_internet" {
  name                    = "allow-outbound-hkp-tcp-from-ci_jenkins_io_ephemeral_agents-subnet-to-internet"
  priority                = 4091
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_port_ranges = [
    "11371", # HKP (OpenPGP KeyServer) - https://github.com/jenkins-infra/helpdesk/issues/3664
  ]
  destination_address_prefixes = local.gpg_keyserver_ips["keyserver.ubuntu.com"]
  resource_group_name          = data.azurerm_resource_group.public.name
  network_security_group_name  = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_ci_jenkins_io_ephemeral_agents_subnet_to_internet" {
  name                        = "allow-outbound-ssh-from-ci_jenkins_io_ephemeral_agents-subnet-to-internet"
  priority                    = 4092
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_port_range      = "22"
  destination_address_prefix  = "Internet" # TODO: restrict to GitHub IPs from their meta endpoint (subsection git) - https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses
  resource_group_name         = data.azurerm_resource_group.public.name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
#tfsec:ignore:azure-network-no-public-egress
resource "azurerm_network_security_rule" "allow_outbound_jenkins_usage_from_ci_agents_subnet_to_ci_controller" {
  name                  = "allow-outbound-jenkins-usage-from-ci-agents-subnet-to-ci-controller"
  priority              = 4093
  direction             = "Outbound"
  access                = "Allow"
  protocol              = "Tcp"
  source_port_range     = "*"
  source_address_prefix = "VirtualNetwork"
  destination_port_ranges = [
    "443",   # Only HTTPS
    "50000", # Direct TCP Inbound protocol
  ]
  destination_address_prefixes = [
    module.ci_jenkins_io.controller_private_ipv4,
    module.ci_jenkins_io.controller_public_ipv4,
  ]
  resource_group_name         = data.azurerm_resource_group.public.name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
resource "azurerm_network_security_rule" "allow_outbound_http_from_ci_jenkins_io_ephemeral_agents_subnet_to_internet" {
  name                    = "allow-outbound-http-from-ci_jenkins_io_ephemeral_agents-subnet-to-internet"
  priority                = 4094
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  source_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_port_ranges = [
    "80",  # HTTP
    "443", # HTTPS
  ]
  destination_address_prefix  = "Internet"
  resource_group_name         = data.azurerm_resource_group.public.name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
resource "azurerm_network_security_rule" "deny_all_outbound_from_ci_jenkins_io_ephemeral_agents_subnet_to_internet" {
  name                        = "deny-all-outbound-from-ci_jenkins_io_ephemeral_agents-subnet-to-internet"
  priority                    = 4095
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = data.azurerm_resource_group.public.name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000.
resource "azurerm_network_security_rule" "deny_all_outbound_from_ci_jenkins_io_ephemeral_agents_subnet_to_vnet" {
  name                         = "deny-all-outbound-from-ci_jenkins_io_ephemeral_agents-subnet-to-vnet"
  priority                     = 4096 # Maximum value allowed by the provider
  direction                    = "Outbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "VirtualNetwork"
  destination_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes
  resource_group_name          = data.azurerm_resource_group.public.name
  network_security_group_name  = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
## Inbound Rules (different set of priorities than Outbound rules) ##
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_privatevpn_to_ephemeral_agents" {
  name                         = "allow-inbound-ssh-from-privatevpn-to-ephemeral-agents"
  priority                     = 4094
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "22"
  source_address_prefixes      = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  destination_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes
  resource_group_name          = data.azurerm_resource_group.public.name
  network_security_group_name  = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000.
resource "azurerm_network_security_rule" "deny_all_inbound_from_internet_to_ci_jenkins_io_ephemeral_agents_subnet" {
  name                        = "deny-all-inbound-from-internet-to-ci_jenkins_io_ephemeral_agents-subnet"
  priority                    = 4095
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.public.name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000
resource "azurerm_network_security_rule" "deny_all_inbound_from_vnet_to_ci_jenkins_io_ephemeral_agents_subnet" {
  name                        = "deny-all-inbound-from-vnet-to-ci_jenkins_io_ephemeral_agents-subnet"
  priority                    = 4096 # Maximum value allowed by the Azure Terraform Provider
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.public.name
  network_security_group_name = azurerm_network_security_group.ci_jenkins_io_ephemeral_agents.name
}
resource "azurerm_storage_account" "ci_jenkins_io_ephemeral_agents" {
  name                     = "cijenkinsioagents"
  resource_group_name      = azurerm_resource_group.ci_jenkins_io_ephemeral_agents.name
  location                 = azurerm_resource_group.ci_jenkins_io_ephemeral_agents.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # default value, needed for tfsec
  tags                     = local.default_tags
}

####################################################################################
## Azure Active Directory Resources to allow controller spawning ephemeral agents
####################################################################################
resource "azuread_application" "ci_jenkins_io" {
  display_name = module.ci_jenkins_io.service_fqdn
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
  tags = [for key, value in local.default_tags : "${key}:${value}"]
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  web {
    homepage_url = "https://github.com/jenkins-infra/azure"
  }
}
resource "azuread_service_principal" "ci_jenkins_io" {
  application_id               = azuread_application.ci_jenkins_io.application_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
}
resource "azuread_application_password" "ci_jenkins_io" {
  application_object_id = azuread_application.ci_jenkins_io.object_id
  display_name          = "${module.ci_jenkins_io.service_fqdn}-tf-managed"
  end_date              = "2024-03-28T00:00:00Z"
}
resource "azurerm_role_assignment" "ci_jenkins_io_read_packer_prod_images" {
  scope                = azurerm_resource_group.packer_images["prod"].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.ci_jenkins_io.id
}
resource "azurerm_role_assignment" "ci_jenkins_io_contributor_in_ephemeral_agent_resourcegroup" {
  scope                = azurerm_resource_group.ci_jenkins_io_ephemeral_agents.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.ci_jenkins_io.id
}
resource "azurerm_role_assignment" "ci_jenkins_io_manage_net_interfaces_subnet_ci_jenkins_io_ephemeral_agents" {
  scope                = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_service_principal.ci_jenkins_io.id
}
resource "azurerm_role_assignment" "ci_jenkins_io_read_publicvnet_subnets" {
  scope              = data.azurerm_virtual_network.public.id
  role_definition_id = azurerm_role_definition.public_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.ci_jenkins_io.id
}
