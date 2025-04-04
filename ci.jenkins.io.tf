moved {
  from = azurerm_resource_group.ci_jenkins_io
  to   = module.ci_jenkins_io_sponsorship.azurerm_resource_group.controller
}
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

  service_fqdn                 = local.ci_jenkins_io_fqdn
  location                     = data.azurerm_virtual_network.public_jenkins_sponsorship.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKvZ23dkvhjSU0Gxl5+mKcBOwmR7gqJDYeA1/Xzl3otV4CtC5te5Vx7YnNEFDXD6BsNkFaliXa34yE37WMdWl+exIURBMhBLmOPxEP/cWA5ZbXP//78ejZsxawBpBJy27uQhdcR0zVoMJc8Q9ShYl5YT/Tq1UcPq2wTNFvnrBJL1FrpGT+6l46BTHI+Wpso8BK64LsfX3hKnJEGuHSM0GAcYQSpXAeGS9zObKyZpk3of/Qw/2sVilIOAgNODbwqyWgEBTjMUln71Mjlt1hsEkv3K/VdvpFNF8VNq5k94VX6Rvg5FQBRL5IrlkuNwGWcBbl8Ydqk4wrD3b/PrtuLBEUsqbNhLnlEvFcjak+u2kzCov73csN/oylR0Tkr2y9x2HfZgDJVtvKjkkc4QERo7AqlTuy1whGfDYsioeabVLjZ9ahPjakv9qwcBrEEF+pAya7Q3AgNFVSdPgLDEwEO8GUHaxAjtyXXv9+yPdoDGmG3Pfn3KqM6UZjHCxne3Dr5ZE="
  controller_network_name      = data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.virtual_network_name
  controller_network_rg_name   = data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.resource_group_name
  controller_subnet_name       = data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.name
  controller_os_disk_size_gb   = 64
  controller_data_disk_size_gb = 512
  controller_vm_size           = "Standard_D8pds_v6"
  is_public                    = true
  enable_public_ipv6           = true
  default_tags                 = local.default_tags
  enable_vm_system_identity    = true

  controller_resourcegroup_name = "ci-jenkins-io"

  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.object_id,
  ]
  controller_service_principal_end_date = "2025-04-07T00:00:00Z"
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
    # acp_service_ips = azurerm_private_dns_a_record.artifact_caching_proxy.records
  }
}

## Service DNS records
resource "azurerm_dns_cname_record" "ci_jenkins_io" {
  name                = trimsuffix(trimsuffix(local.ci_jenkins_io_fqdn, data.azurerm_dns_zone.jenkinsio.name), ".")
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = "aws.ci.jenkins.io"
  tags                = local.default_tags
}
resource "azurerm_dns_cname_record" "assets_ci_jenkins_io" {
  name                = "assets.${azurerm_dns_cname_record.ci_jenkins_io.name}"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = "assets.aws.ci.jenkins.io"
  tags                = local.default_tags
}
resource "azurerm_dns_a_record" "azure_ci_jenkins_io" {
  name                = "azure.ci"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [module.ci_jenkins_io_sponsorship.controller_public_ipv4]
}
resource "azurerm_dns_a_record" "assets_azure_ci_jenkins_io_controller" {
  name                = "assets.azure.ci"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [module.ci_jenkins_io_sponsorship.controller_public_ipv4]
}
resource "azurerm_dns_aaaa_record" "azure_ci_jenkins_io" {
  name                = "azure.ci"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [module.ci_jenkins_io_sponsorship.controller_public_ipv6]
}
resource "azurerm_dns_aaaa_record" "assets_azure_ci_jenkins_io_controller" {
  name                = "assets.azure.ci"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [module.ci_jenkins_io_sponsorship.controller_public_ipv6]
}
resource "azurerm_private_dns_a_record" "artifact_caching_proxy" {
  provider            = azurerm.jenkins-sponsorship
  name                = "artifact-caching-proxy"
  zone_name           = azurerm_private_dns_zone.dockerhub_mirror["cijenkinsio"].name
  resource_group_name = azurerm_private_dns_zone.dockerhub_mirror["cijenkinsio"].resource_group_name
  ttl                 = 60
  records = [
    # Let's specify an IP at the end of the range to have low probability of being used
    cidrhost(
      data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.address_prefixes[0],
      -2,
    )
  ]
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

## Allow ci.jenkins.io to reach aws.ci.jenkins.io
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_cijio_to_awscijio" {
  provider                     = azurerm.jenkins-sponsorship
  name                         = "allow-out-https-from-cijio-to-awscijio"
  priority                     = 3900
  direction                    = "Outbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "22"
  source_address_prefix        = "*"
  destination_address_prefixes = ["3.146.166.108/32"]
  resource_group_name          = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  network_security_group_name  = module.ci_jenkins_io_sponsorship.controller_nsg_name
}

## Allow access to/from ACR endpoint
resource "azurerm_network_security_rule" "allow_out_https_from_cijio_agents_to_acr" {
  provider                = azurerm.jenkins-sponsorship
  name                    = "allow-out-https-from-cijio-agents-to-acr"
  priority                = 4050
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["cijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  network_security_group_name = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}

## Allow access to/from Artifact Caching Proxy (internal LB)
resource "azurerm_network_security_rule" "allow_out_http_from_cijio_agents_to_acp" {
  provider                     = azurerm.jenkins-sponsorship
  name                         = "allow-out-http-from-cijio-agents-to-acp"
  priority                     = 4049
  direction                    = "Outbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "8080"
  source_address_prefixes      = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.address_prefixes
  destination_address_prefixes = azurerm_private_dns_a_record.artifact_caching_proxy.records
  resource_group_name          = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  network_security_group_name  = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}
resource "azurerm_network_security_rule" "allow_in_http_from_cijio_agents_to_acp" {
  provider                     = azurerm.jenkins-sponsorship
  name                         = "allow-in-http-from-cijio-agents-to-acp"
  priority                     = 4049
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "8080"
  source_address_prefixes      = data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.address_prefixes
  destination_address_prefixes = azurerm_private_dns_a_record.artifact_caching_proxy.records
  resource_group_name          = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  network_security_group_name  = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}

####################################################################################
## Resources for Azure File Persistent Volumes (cache, artifacts, etc.)
####################################################################################
resource "azurerm_storage_account" "ci_jenkins_io" {
  provider            = azurerm.jenkins-sponsorship
  name                = "cijenkinsio"
  resource_group_name = module.ci_jenkins_io_sponsorship.controller_resourcegroup_name
  location            = data.azurerm_virtual_network.public_jenkins_sponsorship.location

  account_tier                      = "Premium"
  account_kind                      = "FileStorage"
  access_tier                       = "Hot"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true

  tags = local.default_tags

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    ip_rules = flatten(
      concat(
        [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
      )
    )
    virtual_network_subnet_ids = [
      data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.id,
      data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.id,
      data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id,
      data.azurerm_subnet.privatek8s_tier.id,                                  # required for management from infra.ci (terraform)
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}
resource "azurerm_storage_share" "ci_jenkins_io_maven_cache" {
  provider           = azurerm.jenkins-sponsorship
  name               = "ci-jenkins-io-maven-cache"
  storage_account_id = azurerm_storage_account.ci_jenkins_io.id
  quota              = 100 # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
}
