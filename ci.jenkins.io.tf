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
  controller_network_name      = "${data.azurerm_resource_group.public.name}-vnet"
  controller_network_rg_name   = data.azurerm_resource_group.public.name
  controller_subnet_name       = "${data.azurerm_virtual_network.public.name}-ci_jenkins_io_controller"
  ephemeral_agents_subnet_name = "${data.azurerm_virtual_network.public.name}-ci_jenkins_io_agents"
  controller_os_disk_size_gb   = 64
  controller_data_disk_size_gb = 512
  controller_vm_size           = "Standard_D8as_v5"
  is_public                    = true
  default_tags                 = local.default_tags
  jenkins_infra_ips = {
    ldap_ipv4           = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
    puppet_ipv4         = azurerm_public_ip.puppet_jenkins_io.ip_address
    gpg_keyserver_ipv4s = local.gpg_keyserver_ips["keyserver.ubuntu.com"]
    privatevpn_subnet   = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.id,
  ]
  controller_service_principal_end_date = "2024-03-28T00:00:00Z"
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images["prod"].id
  ]
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
## Outbound Rules (different set of priorities than Inbound rules) ##
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
  network_security_group_name = module.ci_jenkins_io.controller_nsg_name
}

moved {
  from = azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_ci_controller
  to   = module.ci_jenkins_io.azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_controller
}
moved {
  from = azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_ephemeral_agents
  to   = module.ci_jenkins_io.azurerm_network_security_rule.allow_inbound_ssh_from_privatevpn_to_ephemeral_agents
}
