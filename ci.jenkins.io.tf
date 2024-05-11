####################################################################################
## Resources for the Controller VM
####################################################################################
locals {
  ci_jenkins_io_fqdn = "ci.jenkins.io"
  short_name         = "ci"
}

module "ci_jenkins_io_sponsorship" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-controller"
  providers = {
    azurerm     = azurerm.jenkins-sponsorship
    azurerm.dns = azurerm
    azuread     = azuread
  }

  service_fqdn                 = "sponsorship.${local.ci_jenkins_io_fqdn}"
  dns_zone_name                = data.azurerm_dns_zone.jenkinsio.name
  dns_resourcegroup_name       = data.azurerm_resource_group.proddns_jenkinsio.name
  location                     = data.azurerm_virtual_network.public_jenkins_sponsorship.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKvZ23dkvhjSU0Gxl5+mKcBOwmR7gqJDYeA1/Xzl3otV4CtC5te5Vx7YnNEFDXD6BsNkFaliXa34yE37WMdWl+exIURBMhBLmOPxEP/cWA5ZbXP//78ejZsxawBpBJy27uQhdcR0zVoMJc8Q9ShYl5YT/Tq1UcPq2wTNFvnrBJL1FrpGT+6l46BTHI+Wpso8BK64LsfX3hKnJEGuHSM0GAcYQSpXAeGS9zObKyZpk3of/Qw/2sVilIOAgNODbwqyWgEBTjMUln71Mjlt1hsEkv3K/VdvpFNF8VNq5k94VX6Rvg5FQBRL5IrlkuNwGWcBbl8Ydqk4wrD3b/PrtuLBEUsqbNhLnlEvFcjak+u2kzCov73csN/oylR0Tkr2y9x2HfZgDJVtvKjkkc4QERo7AqlTuy1whGfDYsioeabVLjZ9ahPjakv9qwcBrEEF+pAya7Q3AgNFVSdPgLDEwEO8GUHaxAjtyXXv9+yPdoDGmG3Pfn3KqM6UZjHCxne3Dr5ZE="
  controller_network_name      = data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.virtual_network_name
  controller_network_rg_name   = data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.resource_group_name
  controller_subnet_name       = data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.name
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
  controller_service_principal_end_date = "2024-07-22T00:00:00Z"
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images["prod"].id
  ]

  agent_ip_prefixes = concat(
    [local.external_services["s390x.${data.azurerm_dns_zone.jenkinsio.name}"]],
    data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.address_prefixes,
  )
}

module "ci_jenkins_io_azurevm_agents_jenkins_sponsorship" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = local.ci_jenkins_io_fqdn
  service_short_stripped_name      = "ci-jenkins-io"
  ephemeral_agents_network_rg_name = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.name
  controller_rg_name               = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  controller_ips = compact([
    module.ci_jenkins_io_sponsorship.controller_private_ipv4,
    module.ci_jenkins_io_sponsorship.controller_public_ipv4
  ])
  controller_service_principal_id = module.ci_jenkins_io_sponsorship.controller_service_principal_id
  default_tags                    = local.default_tags
  storage_account_name            = "cijenkinsioagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

module "ci_jenkins_io_aci_agents_sponsorship" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-aci-agents"

  role_name                       = "${local.short_name}-ACI-Contributor-sponsorship"
  aci_agents_resource_group_name  = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_resource_group_name
  controller_service_principal_id = module.ci_jenkins_io_sponsorship.controller_service_principal_id
}

module "ci_jenkins_io_kubernetes_agents_jenkins_sponsorship_1" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-inbound-agents"

  service_fqdn                   = local.ci_jenkins_io_fqdn
  inbound_agents_network_rg_name = data.azurerm_resource_group.public_jenkins_sponsorship.name
  inbound_agents_network_name    = data.azurerm_virtual_network.public_jenkins_sponsorship.name
  inbound_agents_subnet_name     = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.name

  controller_rg_name = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  controller_ips = compact([
    module.ci_jenkins_io_sponsorship.controller_private_ipv4,
    module.ci_jenkins_io_sponsorship.controller_public_ipv4
  ])
  default_tags = local.default_tags
}

## Allow ci.jenkins.io to reach the private AKS cluster API (outbound in controller NSG and inbound in cluster subnet)
resource "azurerm_network_security_rule" "allow_outbound_https_from_cijio_to_cijenkinsio_agents_1_api" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-out-https-from-cijio-to-cijenkinsio_agents-1-api"
  priority               = 4000
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "443"
  source_address_prefix  = module.ci_jenkins_io_sponsorship.controller_private_ipv4 # Only private IPv4
  # All IPs has the endpoint NIC may change inside this subnet
  destination_address_prefixes = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.address_prefixes
  resource_group_name          = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  network_security_group_name  = module.ci_jenkins_io_sponsorship.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_inbound_https_from_cijio_to_cijenkinsio_agents_1_api" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-in-https-from-cijio-to-cijenkinsio_agents-1-api"
  priority               = 4000
  direction              = "Inbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "443"
  source_address_prefix  = module.ci_jenkins_io_sponsorship.controller_private_ipv4 # Only private IPv4
  # All IPs has the endpoint NIC may change inside this subnet
  destination_address_prefixes = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.address_prefixes
  resource_group_name          = data.azurerm_resource_group.public_jenkins_sponsorship.name # Passed to module.ci_jenkins_io_kubernetes_agents_jenkins_sponsorship_1
  network_security_group_name  = module.ci_jenkins_io_kubernetes_agents_jenkins_sponsorship_1.inbound_agents_nsg_name
}

## Service DNS records
resource "azurerm_dns_cname_record" "ci_jenkins_io" {
  name                = trimsuffix(trimsuffix(local.ci_jenkins_io_fqdn, data.azurerm_dns_zone.jenkinsio.name), ".")
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = module.ci_jenkins_io_sponsorship.controller_public_fqdn
  tags                = local.default_tags
}
resource "azurerm_dns_cname_record" "assets_ci_jenkins_io" {
  name                = "assets.${azurerm_dns_cname_record.ci_jenkins_io.name}"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = module.ci_jenkins_io_sponsorship.controller_public_fqdn
  tags                = local.default_tags
}
