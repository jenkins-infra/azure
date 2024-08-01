####################################################################################
## Resources for the Controller VM
####################################################################################
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
  controller_service_principal_end_date = "2024-10-19T00:00:00Z"
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

  role_name                       = "ci-ACI-Contributor-sponsorship"
  aci_agents_resource_group_name  = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_resource_group_name
  controller_service_principal_id = module.ci_jenkins_io_sponsorship.controller_service_principal_id
}

## Allow ci.jenkins.io to reach the private AKS cluster API
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

#### ACR to use as DockerHub (and other) Registry mirror
data "azurerm_resource_group" "cijio_agents" {
  name     = "ci-jenkins-io-ephemeral-agents"
  provider = azurerm.jenkins-sponsorship
}

resource "azurerm_container_registry" "cijenkinsio" {
  name                          = "cijenkinsio"
  provider                      = azurerm.jenkins-sponsorship
  resource_group_name           = data.azurerm_resource_group.cijio_agents.name
  location                      = data.azurerm_resource_group.cijio_agents.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false # private links are used to reach the registry
  anonymous_pull_enabled        = true  # Require "Standard" or "Premium" sku. Docker Engine cannot use auth. for pull trough cache - ref. https://github.com/moby/moby/issues/30880
  data_endpoint_enabled         = true  # Required for endpoint private link

  tags = local.default_tags
}

locals {
  # CredentialSet is not supported by Terraform, so we have to specify its name
  acr_cijenkinsio_dockerhub_credentialset = "dockerhub"
}

resource "azurerm_container_registry_cache_rule" "mirror_dockerhub" {
  name                  = "mirror"
  provider              = azurerm.jenkins-sponsorship
  container_registry_id = azurerm_container_registry.cijenkinsio.id
  source_repo           = "docker.io/*"
  target_repo           = "*"
  # Credential created manually (unsupported by Terraform)
  credential_set_id = "${azurerm_container_registry.cijenkinsio.id}/credentialSets/${local.acr_cijenkinsio_dockerhub_credentialset}"
}

resource "azurerm_private_endpoint" "acr_cijenkinsio_agents" {
  name                = "acr-cijenkinsio-agents"
  provider            = azurerm.jenkins-sponsorship
  location            = data.azurerm_resource_group.cijio_agents.location
  resource_group_name = data.azurerm_resource_group.cijio_agents.name
  subnet_id           = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.id

  private_service_connection {
    name                           = "acr-cijenkinsio-agents"
    private_connection_resource_id = azurerm_container_registry.cijenkinsio.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "privatelink.azurecr.io"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr_ci_jenkins_io.id]
  }
  tags = local.default_tags
}

resource "azurerm_private_dns_zone" "acr_ci_jenkins_io" {
  name                = "privatelink.azurecr.io"
  provider            = azurerm.jenkins-sponsorship
  resource_group_name = data.azurerm_resource_group.cijio_agents.name

  tags = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_ci_jenkins_io_vnet_dns" {
  name                  = "acr-ci-jenkins-io-vnet_-dns"
  provider              = azurerm.jenkins-sponsorship
  resource_group_name   = data.azurerm_resource_group.cijio_agents.name
  private_dns_zone_name = azurerm_private_dns_zone.acr_ci_jenkins_io.name
  virtual_network_id    = data.azurerm_virtual_network.public_jenkins_sponsorship.id

  registration_enabled = true
  tags                 = local.default_tags
}

resource "azurerm_key_vault" "ci_jenkins_io" {
  name                = "ddutest" # "ci-jenkins-io"
  provider            = azurerm.jenkins-sponsorship
  location            = data.azurerm_resource_group.cijio_agents.location
  resource_group_name = data.azurerm_resource_group.cijio_agents.name

  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false
  enable_rbac_authorization       = true
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true

  sku_name = "standard"

  tags = local.default_tags
}

resource "azurerm_network_security_rule" "allow_out_https_from_cijio_agents_to_acr" {
  provider                = azurerm.jenkins-sponsorship
  name                    = "allow-out-https-from-cijio-agents-to-acr"
  priority                = 4050
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.acr_cijenkinsio_agents.private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  network_security_group_name = module.ci_jenkins_io_sponsorship.controller_nsg_name
}

resource "azurerm_network_security_rule" "allow_in_https_from_cijio_agents_to_acr" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-in-https-from-cijio-agents-to-acr"
  priority               = 4050
  direction              = "Inbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "443"
  source_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.acr_cijenkinsio_agents.private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  destination_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents.address_prefixes
  resource_group_name          = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  network_security_group_name  = module.ci_jenkins_io_sponsorship.controller_nsg_name
}

# This role allows the ACR registry to read secrets
# Note: an admin must insert secrets into the keyvault manually and then create the credentialset in ACR manually
#  which requires the "Key Vault Secrets Officer"  or "Owner" role temporarily
resource "azurerm_role_assignment" "acr_read_keyvault_secrets" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = azurerm_key_vault.ci_jenkins_io.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = "201fed0a-6e86-4600-a12b-945f2c1c0eb2"
  skip_service_principal_aad_check = true
}
