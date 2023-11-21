# Data of resources defined in https://github.com/jenkins-infra/azure-net
data "azurerm_resource_group" "cert_ci_jenkins_io" {
  name = "cert-ci-jenkins-io"
}
data "azurerm_dns_zone" "cert_ci_jenkins_io" {
  name                = "cert.ci.jenkins.io"
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
}
data "azurerm_virtual_network" "cert_ci_jenkins_io" {
  name                = "cert-ci-jenkins-io-vnet"
  resource_group_name = data.azurerm_resource_group.cert_ci_jenkins_io.name
}
data "azurerm_subnet" "cert_ci_jenkins_io_controller" {
  name                 = "cert-ci-jenkins-io-vnet-controller"
  virtual_network_name = data.azurerm_virtual_network.cert_ci_jenkins_io.name
  resource_group_name  = data.azurerm_resource_group.cert_ci_jenkins_io.name
}
data "azurerm_subnet" "cert_ci_jenkins_io_ephemeral_agents" {
  name                 = "cert-ci-jenkins-io-vnet-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.cert_ci_jenkins_io.name
  resource_group_name  = data.azurerm_resource_group.cert_ci_jenkins_io.name
}

module "cert_ci_jenkins_io" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-controller"

  service_fqdn                 = data.azurerm_dns_zone.cert_ci_jenkins_io.name
  location                     = data.azurerm_resource_group.cert_ci_jenkins_io.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDpxwvySus2OWViWfJ02XMYr+Qa/uPADhjt/4el2SmEf7NlJXzq5vc8imcw8YxQZKwuuKJhonlTYTpk1Cjka4bJKWNOSQ8+Kx0O2ZnNjKn3ZETWJB90bZXHVqbrNHDtu6lN6S/yRW9Q+6fuDbHBW0MXWI8Lsv+bU5v8Zll6m62rc00/I/IT9c1TX1qjCtjf5XHMFw7nVxQiTX2Zf5UKG3RI7mkCMDIvx2H9kXdzM8jtYwATZPHKHuLzffARmvy1FpNPVuLLEGYE3hljP82rll1WZbbl1ZrhjzbFUUYO4fsA7AOQHWhHiVLvtnreB269JOl/ZkHgk37zcdwJMkqKpqoEbjP9z8PURf5uMA7TiDGcpgcFMzoaFk1ueqoHM2JaM2AZQAkPhbUfT7MSOFYRx91OEg5pg5N17zNeaBM6fyxl3v7mkxSOTkKlzjAXPRyo7XsosUVQ4qb4DfsAAJ0Rynts2olRQLEzJku0ZxbbXotuoppI8HivRl7PoTsAASJRpc="
  controller_network_name      = data.azurerm_virtual_network.cert_ci_jenkins_io.name
  controller_network_rg_name   = data.azurerm_resource_group.cert_ci_jenkins_io.name
  controller_subnet_name       = data.azurerm_subnet.cert_ci_jenkins_io_controller.name
  controller_data_disk_size_gb = 128
  controller_vm_size           = "Standard_D2as_v5"
  default_tags                 = local.default_tags

  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }

  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.id,
  ]
  controller_service_principal_end_date = "2024-08-24T12:00:00Z"
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images["prod"].id
  ]

  agent_ip_prefixes = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.address_prefixes
}

module "cert_ci_jenkins_io_azurevm_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  # Same RG as the controller to avoid accidental deletion when managing VMs for agents

  service_fqdn                     = module.cert_ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.cert_ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.name
  controller_rg_name               = module.cert_ci_jenkins_io.controller_resourcegroup_name
  controller_ips                   = compact([module.cert_ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.cert_ci_jenkins_io.controler_service_principal_id
  default_tags                     = local.default_tags
  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

module "cert_ci_jenkins_io_aci_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-aci-agents"

  service_short_stripped_name     = module.cert_ci_jenkins_io.service_short_stripped_name
  aci_agents_resource_group_name  = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_resource_group_name
  controller_service_principal_id = module.cert_ci_jenkins_io.controler_service_principal_id
}

### ACI Agents
moved {
  from = module.cert_ci_jenkins_io.azurerm_role_definition.ephemeral_agents_aci_contributor
  to   = module.cert_ci_jenkins_io_aci_agents.azurerm_role_definition.ephemeral_agents_aci_contributor
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_role_assignment.controller_ephemeral_agents_aci_contributor
  to   = module.cert_ci_jenkins_io_aci_agents.azurerm_role_assignment.controller_ephemeral_agents_aci_contributor
}

### Ephemeral Agents
# Resources
moved {
  from = module.cert_ci_jenkins_io.azurerm_resource_group.ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_resource_group.ephemeral_agents
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_storage_account.ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_storage_account.ephemeral_agents
}

# AzureAD
moved {
  from = module.cert_ci_jenkins_io.azurerm_role_assignment.controller_contributor_in_ephemeral_agent_resourcegroup
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_role_assignment.controller_contributor_in_ephemeral_agent_resourcegroup
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_role_assignment.controller_io_manage_net_interfaces_subnet_ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_role_assignment.controller_io_manage_net_interfaces_subnet_ephemeral_agents
}

# NSGs
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_group.ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_group.ephemeral_agents
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_subnet_network_security_group_association.ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_subnet_network_security_group_association.ephemeral_agents
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_inbound_ssh_from_controller_to_ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_inbound_ssh_from_controller_to_ephemeral_agents
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_outbound_hkp_tcp_from_ephemeral_agents_subnet_to_internet
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_hkp_tcp_from_ephemeral_agents_subnet_to_internet
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_outbound_hkp_udp_from_ephemeral_agents_subnet_to_internet
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_hkp_udp_from_ephemeral_agents_subnet_to_internet
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_outbound_http_from_ephemeral_agents_to_internet
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_http_from_ephemeral_agents_to_internet
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_outbound_jenkins_from_ephemeral_agents_to_controller
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_jenkins_from_ephemeral_agents_to_controller
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_outbound_ssh_from_ephemeral_agents_to_internet
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_ssh_from_ephemeral_agents_to_internet
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.deny_all_inbound_from_vnet_to_ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_inbound_from_vnet_to_ephemeral_agents
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_internet
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_internet
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_ephemeral_agents
  to   = module.cert_ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_ephemeral_agents
}
moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_outbound_ssh_from_controller_to_ephemeral_agents
  to   = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_outbound_ssh_from_controller_to_agents
}

## Service DNS records
resource "azurerm_dns_a_record" "cert_ci_jenkins_io_controller" {
  name                = "controller"
  zone_name           = data.azurerm_dns_zone.cert_ci_jenkins_io.name
  resource_group_name = data.azurerm_dns_zone.cert_ci_jenkins_io.resource_group_name
  ttl                 = 60
  records             = [module.cert_ci_jenkins_io.controller_private_ipv4]
}
resource "azurerm_dns_a_record" "cert_ci_jenkins_io" {
  name                = "@" # Child zone: no CNAME possible!
  zone_name           = data.azurerm_dns_zone.cert_ci_jenkins_io.name
  resource_group_name = data.azurerm_dns_zone.cert_ci_jenkins_io.resource_group_name
  ttl                 = 60
  records             = [module.cert_ci_jenkins_io.controller_private_ipv4]
}

####################################################################################
## NAT gateway to allow outbound connection on a centralized and scalable appliance
####################################################################################
resource "azurerm_public_ip" "cert_ci_jenkins_io_outbound" {
  name                = "cert-ci-jenkins-io-outbound"
  location            = data.azurerm_resource_group.cert_ci_jenkins_io.location
  resource_group_name = module.cert_ci_jenkins_io.controller_resourcegroup_name
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_nat_gateway" "cert_ci_jenkins_io_outbound" {
  name                = "cert-ci-jenkins-io-outbound"
  location            = data.azurerm_resource_group.cert_ci_jenkins_io.location
  resource_group_name = module.cert_ci_jenkins_io.controller_resourcegroup_name
  sku_name            = "Standard"
}
resource "azurerm_nat_gateway_public_ip_association" "cert_ci_jenkins_io_outbound" {
  nat_gateway_id       = azurerm_nat_gateway.cert_ci_jenkins_io_outbound.id
  public_ip_address_id = azurerm_public_ip.cert_ci_jenkins_io_outbound.id
}
resource "azurerm_subnet_nat_gateway_association" "cert_ci_jenkins_io_outbound_controller" {
  subnet_id      = data.azurerm_subnet.cert_ci_jenkins_io_controller.id
  nat_gateway_id = azurerm_nat_gateway.cert_ci_jenkins_io_outbound.id
}
resource "azurerm_subnet_nat_gateway_association" "cert_ci_jenkins_io_outbound_ephemeral_agents" {
  subnet_id      = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.id
  nat_gateway_id = azurerm_nat_gateway.cert_ci_jenkins_io_outbound.id
}
