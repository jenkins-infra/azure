####################################################################################
## Resources for the Controller VM in the CDF subscription
####################################################################################
module "trusted_ci_jenkins_io_letsencrypt" {
  source = "./modules/azure-letsencrypt-dns"

  default_tags     = local.default_tags
  zone_name        = "trusted.ci.jenkins.io"
  dns_rg_name      = data.azurerm_resource_group.proddns_jenkinsio.name
  parent_zone_name = data.azurerm_dns_zone.jenkinsio.name
  principal_id     = module.trusted_ci_jenkins_io.controller_service_principal_id
}
module "trusted_ci_jenkins_io" {
  source = "./modules/azure-jenkinsinfra-controller"

  providers = {
    azurerm     = azurerm
    azurerm.dns = azurerm
    azuread     = azuread
  }

  service_fqdn                 = "trusted.ci.jenkins.io"
  location                     = data.azurerm_virtual_network.trusted_ci_jenkins_io.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ=="
  controller_network_name      = data.azurerm_virtual_network.trusted_ci_jenkins_io.name
  controller_network_rg_name   = data.azurerm_resource_group.trusted_ci_jenkins_io.name
  controller_subnet_name       = data.azurerm_subnet.trusted_ci_jenkins_io_controller.name
  controller_data_disk_size_gb = 128
  controller_vm_size           = "Standard_B2s"
  default_tags                 = local.default_tags

  controller_resourcegroup_name = "jenkinsinfra-trusted-ci-controller"
  controller_datadisk_name      = "trusted-ci-controller-data-disk"

  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.publick8s_ips["publick8s-ldap-ipv4"].ip_address,
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address,
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
  }

  controller_service_principal_ids = [
    # Commenting out to migrate to new AzureAD provider
    # data.azuread_service_principal.terraform_production.id,
    "b847a030-25e1-4791-ad04-9e8484d87bce",
  ]
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images_sponsored["prod"].id,
  ]

  agent_ip_prefixes = concat(
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.address_prefixes,
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_permanent_agents.address_prefixes,
  )
}

####################################################################################
## Common resources (endpoint, DNS, etc.) in the sponsored subscription
####################################################################################
resource "azurerm_resource_group" "trusted_ci_jenkins_io_sponsored_commons" {
  provider = azurerm.jenkins-sponsored
  name     = "trusted-ci-jenkins-io-sponsored-commons"
  location = var.location
  tags     = local.default_tags
}
# Managed in jenkins-infra/azure-net with vnet and subnets
data "azurerm_network_security_group" "trusted_ci_jenkins_io_sponsored_vnet" {
  provider = azurerm.jenkins-sponsored

  name                = "trusted-ci-jenkins-io-sponsored-vnet"
  resource_group_name = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.resource_group_name
}
# Allow agents to access archives.jenkins.io for rsync-over-SSH
resource "azurerm_network_security_rule" "allow_out_many_from_trusted_agents_sponsored_to_archives_jenkins_io" {
  provider = azurerm.jenkins-sponsored

  name              = "allow-out-many-from-agents-sponsored-to-archives-jenkins-io"
  priority          = 4071
  direction         = "Outbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  destination_port_ranges = [
    "22", # SSH (for rsync)
  ]
  source_address_prefixes = concat(
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.address_prefixes,
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_permanent_agents.address_prefixes,
  )
  destination_address_prefix  = local.external_services["archives.jenkins.io"]
  resource_group_name         = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.resource_group_name
  network_security_group_name = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.name
}
# Allow access to the private Azure Container Registry through an Azure Private Endpoint NIC
module "trustedcijenkinsiosponsored_acr_pe" {
  source = "./modules/azure-container-registry-private-links"

  providers = {
    azurerm     = azurerm.jenkins-sponsored
    azurerm.acr = azurerm
  }

  name = "trustedcijenkinsiosponsored"

  acr_name     = azurerm_container_registry.dockerhub_mirror.name
  acr_location = azurerm_container_registry.dockerhub_mirror.location
  acr_rg_name  = azurerm_container_registry.dockerhub_mirror.resource_group_name

  subnet_name  = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_commons.name
  vnet_name    = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsored.name
  vnet_rg_name = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsored.resource_group_name

  default_tags = local.default_tags
}
## Allow access to/from Private Endpoint
resource "azurerm_network_security_rule" "allow_out_https_from_trusted_sponsored_vnet_to_acr" {
  provider = azurerm.jenkins-sponsored

  name                         = "allow-out-https-from-sponsored-vnet-to-acr"
  priority                     = 4052
  direction                    = "Outbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "443"
  source_address_prefixes      = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsored.address_space
  destination_address_prefixes = split(",", module.trustedcijenkinsiosponsored_acr_pe.private_endpoint_nic_ip_addresses)
  resource_group_name          = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.resource_group_name
  network_security_group_name  = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.name
}
resource "azurerm_network_security_rule" "allow_in_https_from_trusted_sponsored_vnet_to_acr" {
  provider = azurerm.jenkins-sponsored

  name                         = "allow-in-https-from-sponsored-vnet-to-acr"
  priority                     = 4052
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "443"
  source_address_prefixes      = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsored.address_space
  destination_address_prefixes = split(",", module.trustedcijenkinsiosponsored_acr_pe.private_endpoint_nic_ip_addresses)
  resource_group_name          = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.resource_group_name
  network_security_group_name  = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.name
}
## updates.jenkins.io's mirrorbits CLI Kubernetes Service (internal LB)
data "azurerm_private_link_service" "publick8s_mirrorbitscli_updates_jenkins_io" {
  # TODO: track with updatecli from https://github.com/jenkins-infra/kubernetes-management/config/publick8s_updates-jenkins-io.yaml
  name                = "publick8s-updates.jenkins.io"
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
}
resource "azurerm_private_endpoint" "publick8s_updates_jenkins_io_for_trustedci_sponsored" {
  provider = azurerm.jenkins-sponsored

  name = "${data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.name}-for-trustedci-sponsored"

  location            = var.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_sponsored_commons.name
  subnet_id           = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_commons.id

  custom_network_interface_name = "${data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.name}-for-trustedci-sponsored"

  private_service_connection {
    name                           = "${data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.name}-for-trustedci-sponsored"
    private_connection_resource_id = data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.id
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = module.trustedcijenkinsiosponsored_acr_pe.private_dns_zone_name
    private_dns_zone_ids = [module.trustedcijenkinsiosponsored_acr_pe.private_dns_zone_id]
  }
  tags = local.default_tags
}
resource "azurerm_private_dns_a_record" "updates_jenkins_io_sponsored" {
  provider = azurerm.jenkins-sponsored

  name      = "updates.jenkins.io"                                            # Expected full record name: updates.jenkins.io.privatelink.azurecr.io
  zone_name = module.trustedcijenkinsiosponsored_acr_pe.private_dns_zone_name # This existing zone already associated to the vnet
  # Must be the same as the private zone (otherwise: 404 when applying)
  resource_group_name = module.trustedcijenkinsiosponsored_acr_pe.private_dns_zone_resource_group_name
  ttl                 = 60
  records             = [azurerm_private_endpoint.publick8s_updates_jenkins_io_for_trustedci_sponsored.private_service_connection[0].private_ip_address]
}
## Allow access to/from UC Private Endpoint
resource "azurerm_network_security_rule" "allow_in_many_from_trusted_agents_sponsored_to_uc" {
  provider = azurerm.jenkins-sponsored

  name              = "allow-in-many-from-trusted-agents-sponsored-to-uc"
  priority          = 4054
  direction         = "Inbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  destination_port_ranges = [
    "3390", # mirrorbits CLI (content)
  ]
  source_address_prefixes = concat(
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.address_prefixes,
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_permanent_agents.address_prefixes,
  )
  destination_address_prefix  = azurerm_private_endpoint.publick8s_updates_jenkins_io_for_trustedci_sponsored.private_service_connection[0].private_ip_address
  resource_group_name         = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.resource_group_name
  network_security_group_name = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.name
}
resource "azurerm_network_security_rule" "allow_out_from_trusted_agents_sponsored_to_uc" {
  provider = azurerm.jenkins-sponsored

  name              = "allow-out-from-trusted-agents-sponsored-to-uc"
  priority          = 4054
  direction         = "Outbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  destination_port_ranges = [
    "3390", # mirrorbits CLI (content)
  ]
  source_address_prefixes = concat(
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.address_prefixes,
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_permanent_agents.address_prefixes,
  )
  destination_address_prefix  = azurerm_private_endpoint.publick8s_updates_jenkins_io_for_trustedci_sponsored.private_service_connection[0].private_ip_address
  resource_group_name         = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.resource_group_name
  network_security_group_name = data.azurerm_network_security_group.trusted_ci_jenkins_io_sponsored_vnet.name
}
# Resource for the agent "UAID" (User Assigned IDentity) allowing credential-less access to other Azure resources from agent VMs
resource "azurerm_user_assigned_identity" "trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored" {
  provider = azurerm.jenkins-sponsored

  location            = azurerm_resource_group.trusted_ci_jenkins_io_sponsored_commons.location
  name                = "trusted-ci-jenkins-io-agents-sponsored"
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_sponsored_commons.name
}
# The controller UAID need permissions to assign the agent UAID (distinct from controller's) to VM agents - https://plugins.jenkins.io/azure-vm-agents/#plugin-content-roles-required-by-feature
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_operate_agent_identity_jenkins_sponsored" {
  provider = azurerm.jenkins-sponsored

  scope                = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = module.trusted_ci_jenkins_io.controller_service_principal_id
}
####################################################################################
## Agents resources in the sponsored subscription
####################################################################################
module "trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored" {
  providers = {
    azurerm = azurerm.jenkins-sponsored
  }
  source = "./modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.trusted_ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.trusted_ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.name
  use_vnet_common_nsg              = true
  controller_ips                   = compact([module.trusted_ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.trusted_ci_jenkins_io.controller_service_principal_id
  default_tags                     = local.default_tags
  storage_account_name             = "trustedciagentssponso" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored_write_reports_share" {
  provider = azurerm.jenkins-sponsored
  scope    = azurerm_storage_account.reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored.principal_id
}
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored_write_buildsreports_share" {
  provider = azurerm.jenkins-sponsored
  scope    = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored.principal_id
}
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored_write_data_storage_share" {
  provider = azurerm.jenkins-sponsored
  scope    = azurerm_storage_account.data_storage_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored.principal_id
}
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored_write_javadoc_share" {
  scope = azurerm_storage_account.javadoc_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored.principal_id
}

resource "azurerm_role_definition" "trusted_ci_jenkins_io_controller_vnet_sponsored_reader" {
  provider = azurerm.jenkins-sponsored
  name     = "Read-trusted-ci-jenkins-io-sponsored-VNET"
  scope    = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsored.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "trusted_controller_vnet_jenkins_sponsored_reader" {
  provider           = azurerm.jenkins-sponsored
  scope              = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsored.id
  role_definition_id = azurerm_role_definition.trusted_ci_jenkins_io_controller_vnet_sponsored_reader.role_definition_resource_id
  principal_id       = module.trusted_ci_jenkins_io.controller_service_principal_id
}

####################################################################################
## Public DNS records in the CDF subscription
####################################################################################
resource "azurerm_dns_a_record" "trusted_ci_controller" {
  name                = "@"
  zone_name           = module.trusted_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [module.trusted_ci_jenkins_io.controller_private_ipv4]
}
resource "azurerm_dns_a_record" "assets_trusted_ci_controller" {
  name                = "assets"
  zone_name           = module.trusted_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [module.trusted_ci_jenkins_io.controller_private_ipv4]
}
