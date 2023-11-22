####################################################################################
## Resources for the Controller VM
####################################################################################
data "azurerm_subnet" "ci_jenkins_io_ephemeral_agents" {
  name                 = "${data.azurerm_virtual_network.public.name}-ci_jenkins_io_agents"
  virtual_network_name = data.azurerm_virtual_network.public.name
  resource_group_name  = data.azurerm_virtual_network.public.resource_group_name
}

data "azurerm_subnet" "ci_jenkins_io_ephemeral_agents_jenkins_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.public_jenkins_sponsorship.name}-ci_jenkins_io_agents"
  virtual_network_name = data.azurerm_virtual_network.public_jenkins_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.public_jenkins_sponsorship.resource_group_name
}

module "ci_jenkins_io" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-controller"

  service_fqdn                 = "ci.jenkins.io"
  location                     = data.azurerm_virtual_network.public.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKvZ23dkvhjSU0Gxl5+mKcBOwmR7gqJDYeA1/Xzl3otV4CtC5te5Vx7YnNEFDXD6BsNkFaliXa34yE37WMdWl+exIURBMhBLmOPxEP/cWA5ZbXP//78ejZsxawBpBJy27uQhdcR0zVoMJc8Q9ShYl5YT/Tq1UcPq2wTNFvnrBJL1FrpGT+6l46BTHI+Wpso8BK64LsfX3hKnJEGuHSM0GAcYQSpXAeGS9zObKyZpk3of/Qw/2sVilIOAgNODbwqyWgEBTjMUln71Mjlt1hsEkv3K/VdvpFNF8VNq5k94VX6Rvg5FQBRL5IrlkuNwGWcBbl8Ydqk4wrD3b/PrtuLBEUsqbNhLnlEvFcjak+u2kzCov73csN/oylR0Tkr2y9x2HfZgDJVtvKjkkc4QERo7AqlTuy1whGfDYsioeabVLjZ9ahPjakv9qwcBrEEF+pAya7Q3AgNFVSdPgLDEwEO8GUHaxAjtyXXv9+yPdoDGmG3Pfn3KqM6UZjHCxne3Dr5ZE="
  dns_zone_name                = data.azurerm_dns_zone.jenkinsio.name
  dns_resourcegroup_name       = data.azurerm_resource_group.proddns_jenkinsio.name
  controller_network_name      = "${data.azurerm_resource_group.public.name}-vnet"
  controller_network_rg_name   = data.azurerm_resource_group.public.name
  controller_subnet_name       = "${data.azurerm_virtual_network.public.name}-ci_jenkins_io_controller"
  controller_os_disk_size_gb   = 64
  controller_data_disk_size_gb = 512
  controller_vm_size           = "Standard_D8as_v5"
  is_public                    = true
  default_tags                 = local.default_tags
  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.id,
  ]
  controller_service_principal_end_date = "2024-03-28T00:00:00Z"
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images["prod"].id
  ]

  agent_ip_prefixes = concat(
    [local.external_services["s390x.${data.azurerm_dns_zone.jenkinsio.name}"]],
    data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes,
  )
}

module "ci_jenkins_io_azurevm_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.name
  controller_rg_name               = module.ci_jenkins_io.controller_resourcegroup_name
  controller_ips                   = compact([module.ci_jenkins_io.controller_private_ipv4, module.ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.ci_jenkins_io.controler_service_principal_id
  default_tags                     = local.default_tags

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

resource "azurerm_resource_group" "controller_jenkins_sponsorship" {
  name     = module.ci_jenkins_io.controller_resourcegroup_name # Same name on both subscriptions
  location = var.location
  tags     = local.default_tags
}

module "ci_jenkins_io_azurevm_agents_jenkins_sponsorship" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.name
  controller_rg_name               = azurerm_resource_group.controller_jenkins_sponsorship.name
  controller_ips                   = compact([module.ci_jenkins_io.controller_private_ipv4, module.ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.ci_jenkins_io.controler_service_principal_id
  default_tags                     = local.default_tags

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

module "ci_jenkins_io_aci_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-aci-agents"

  service_short_stripped_name     = module.ci_jenkins_io.service_short_stripped_name
  aci_agents_resource_group_name  = module.ci_jenkins_io_azurevm_agents.ephemeral_agents_resource_group_name
  controller_service_principal_id = module.ci_jenkins_io.controler_service_principal_id
}

### ACI Agents
moved {
  from = module.ci_jenkins_io.azurerm_role_definition.ephemeral_agents_aci_contributor
  to   = module.ci_jenkins_io_aci_agents.azurerm_role_definition.ephemeral_agents_aci_contributor
}
moved {
  from = module.ci_jenkins_io.azurerm_role_assignment.controller_ephemeral_agents_aci_contributor
  to   = module.ci_jenkins_io_aci_agents.azurerm_role_assignment.controller_ephemeral_agents_aci_contributor
}

### Ephemeral Agents
# Resources
moved {
  from = module.ci_jenkins_io.azurerm_resource_group.ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_resource_group.ephemeral_agents
}
moved {
  from = module.ci_jenkins_io.azurerm_storage_account.ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_storage_account.ephemeral_agents
}

# AzureAD
moved {
  from = module.ci_jenkins_io.azurerm_role_assignment.controller_contributor_in_ephemeral_agent_resourcegroup
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_role_assignment.controller_contributor_in_ephemeral_agent_resourcegroup
}
moved {
  from = module.ci_jenkins_io.azurerm_role_assignment.controller_io_manage_net_interfaces_subnet_ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_role_assignment.controller_io_manage_net_interfaces_subnet_ephemeral_agents
}

# NSGs
moved {
  from = module.ci_jenkins_io.azurerm_network_security_group.ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_group.ephemeral_agents
}
moved {
  from = module.ci_jenkins_io.azurerm_subnet_network_security_group_association.ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_subnet_network_security_group_association.ephemeral_agents
}
moved {
  from = module.ci_jenkins_io.azurerm_resource_group.ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_resource_group.ephemeral_agents
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_inbound_ssh_from_controller_to_ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_inbound_ssh_from_controller_to_ephemeral_agents
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_outbound_hkp_tcp_from_ephemeral_agents_subnet_to_internet
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_hkp_tcp_from_ephemeral_agents_subnet_to_internet
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_outbound_hkp_udp_from_ephemeral_agents_subnet_to_internet
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_hkp_udp_from_ephemeral_agents_subnet_to_internet
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_outbound_http_from_ephemeral_agents_to_internet
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_http_from_ephemeral_agents_to_internet
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_outbound_jenkins_from_ephemeral_agents_to_controller
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_jenkins_from_ephemeral_agents_to_controller
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_outbound_ssh_from_ephemeral_agents_to_internet
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_outbound_ssh_from_ephemeral_agents_to_internet
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.deny_all_inbound_from_vnet_to_ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_inbound_from_vnet_to_ephemeral_agents
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_internet
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_internet
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.deny_all_outbound_from_ephemeral_agents_to_vnet
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_ephemeral_agents
  to   = module.ci_jenkins_io_azurevm_agents.azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_ephemeral_agents
}
moved {
  from = module.ci_jenkins_io.azurerm_network_security_rule.allow_outbound_ssh_from_controller_to_ephemeral_agents
  to   = module.ci_jenkins_io.azurerm_network_security_rule.allow_outbound_ssh_from_controller_to_agents
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
