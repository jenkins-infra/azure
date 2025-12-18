####################################################################################
## Resources for the Controller VM
####################################################################################
module "trusted_ci_jenkins_io_letsencrypt" {
  source = "./.shared-tools/terraform/modules/azure-letsencrypt-dns"

  default_tags     = local.default_tags
  zone_name        = "trusted.ci.jenkins.io"
  dns_rg_name      = data.azurerm_resource_group.proddns_jenkinsio.name
  parent_zone_name = data.azurerm_dns_zone.jenkinsio.name
  principal_id     = module.trusted_ci_jenkins_io.controller_service_principal_id
}
module "trusted_ci_jenkins_io" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-controller"

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
    azurerm_resource_group.packer_images_cdf["prod"].id,
  ]

  agent_ip_prefixes = concat(
    data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefixes,
    [
      azurerm_linux_virtual_machine.agent_trusted_ci_jenkins_io.private_ip_address
    ],
  )
}

module "trusted_ci_jenkins_io_azurevm_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.trusted_ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.trusted_ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.name
  controller_rg_name               = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  controller_ips                   = compact([module.trusted_ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.trusted_ci_jenkins_io.controller_service_principal_id
  default_tags                     = local.default_tags
  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}
# Required to allow controller to check for subnets inside the agents virtual network
resource "azurerm_role_definition" "trusted_ci_jenkins_io_controller_vnet_reader" {
  name  = "Read-trusted-ci-jenkins-io-VNET"
  scope = data.azurerm_virtual_network.trusted_ci_jenkins_io.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "trusted_controller_ephemeral_agents_vnet_reader" {
  scope              = data.azurerm_virtual_network.trusted_ci_jenkins_io.id
  role_definition_id = azurerm_role_definition.trusted_ci_jenkins_io_controller_vnet_reader.role_definition_resource_id
  principal_id       = module.trusted_ci_jenkins_io.controller_service_principal_id
}
# Allow controller to manage agents without requiring credentials (requires on the VM User Assign Identity)
resource "azurerm_user_assigned_identity" "trusted_ci_jenkins_io_azurevm_agents_jenkins" {
  location            = data.azurerm_virtual_network.trusted_ci_jenkins_io.location
  name                = "trusted-ci-jenkins-io-agents"
  resource_group_name = module.trusted_ci_jenkins_io.controller_resourcegroup_name
}
# The Controller identity must be able to operate this identity to assign it to VM agents - https://plugins.jenkins.io/azure-vm-agents/#plugin-content-roles-required-by-feature
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_manage_agent_uaid" {
  scope                = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = module.trusted_ci_jenkins_io.controller_service_principal_id
}
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_azurevm_agents_jenkins_write_buildsreports_share" {
  scope = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins.principal_id
}

# Custom role required to allow returning the Service SAS token of javadocjenkinsio storage account
resource "azurerm_role_definition" "javadoc_jenkins_io_list_service_sas_action" {
  name        = "javadocjenkinsio-list-service-sas-action-role"
  scope       = azurerm_storage_account.javadoc_jenkins_io.id
  description = "Custome role to allow returning the Service SAS token for javadocjenkinsio storage account."

  permissions {
    actions     = ["Microsoft.Storage/storageAccounts/listServiceSas/action"]
    not_actions = []
  }

  assignable_scopes = [
    azurerm_storage_account.javadoc_jenkins_io.id
  ]
}

resource "azurerm_role_assignment" "trusted_ci_jenkins_io_azurevm_agents_jenkins_javadoc_jenkins_io_list_service_sas_action" {
  scope = azurerm_storage_account.javadoc_jenkins_io.id
  # Allow writing
  role_definition_id = azurerm_role_definition.javadoc_jenkins_io_list_service_sas_action
  principal_id       = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins.principal_id
}

resource "azurerm_role_assignment" "trusted_ci_jenkins_io_azurevm_agents_jenkins_write_javadoc_share" {
  scope = azurerm_storage_account.javadoc_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins.principal_id
}

## TODO: move to credential-less
# Required to allow azcopy sync of javadoc.jenkins.io File Share
module "trustedci_javadocjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn               = "trustedci-javadocjenkinsio-fileshare_serviceprincipal_writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = "2025-12-23T00:00:00Z"
  file_share_id              = azurerm_storage_share.javadoc_jenkins_io.id
  storage_account_id         = azurerm_storage_account.javadoc_jenkins_io.id
  default_tags               = local.default_tags
}

## TODO: move to credential-less
# Required to allow azcopy sync to the reports.jenkins.io File Share
module "trustedci_reportsjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn               = "trustedci-reportsjenkinsio-fileshare_serviceprincipal_writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = "2025-12-23T00:00:00Z"
  file_share_id              = azurerm_storage_share.reports_jenkins_io.id
  storage_account_id         = azurerm_storage_account.reports_jenkins_io.id
  default_tags               = local.default_tags
}

####################################################################################
## Network Security Group and rules
####################################################################################
## Outbound Rules (different set of priorities than Inbound rules) ##
resource "azurerm_network_security_rule" "allow_out_from_trusted_all_to_uc" {
  name              = "allow-out-from-trusted-all-to-uc"
  priority          = 4050
  direction         = "Outbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  destination_port_ranges = [
    "3390", # mirrorbits CLI (content)
  ]
  source_address_prefixes = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_address_prefixes = [
    # Update Center (mirrorbits CLI)
    azurerm_private_endpoint.publick8s_updates_jenkins_io_for_trustedci.private_service_connection[0].private_ip_address,
  ]
  resource_group_name         = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}
resource "azurerm_network_security_rule" "allow_out_many_from_trusted_agents_to_pkg" {
  name              = "allow-out-many-from-agents-to-pkg"
  priority          = 4055
  direction         = "Outbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  destination_port_ranges = [
    "22", # SSH (for rsync)
  ]
  source_address_prefixes     = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_address_prefix  = local.external_services["pkg.origin.jenkins.io"]
  resource_group_name         = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}
resource "azurerm_network_security_rule" "allow_out_many_from_trusted_agents_to_archive" {
  name              = "allow-out-many-from-agents-to-archive"
  priority          = 4060
  direction         = "Outbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  destination_port_ranges = [
    "22", # SSH (for rsync)
  ]
  source_address_prefixes     = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_address_prefix  = local.external_services["archives.jenkins.io"]
  resource_group_name         = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}
## Inbound Rules (different set of priorities than Outbound rules) ##
resource "azurerm_network_security_rule" "allow_in_many_from_trusted_agents_to_uc" {
  name              = "allow-in-many-from-trusted-agents-to-uc"
  priority          = 4050
  direction         = "Inbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  destination_port_ranges = [
    "3390", # mirrorbits CLI (content)
  ]
  source_address_prefixes = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_address_prefixes = [
    # Update Center (mirrorbits CLI)
    azurerm_private_endpoint.publick8s_updates_jenkins_io_for_trustedci.private_service_connection[0].private_ip_address,
  ]
  resource_group_name         = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

## Allow access to/from ACR endpoint
resource "azurerm_network_security_rule" "allow_out_https_from_trusted_to_acr" {
  name                    = "allow-out-https-from-vnet-to-acr"
  priority                = 4051
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_virtual_network.trusted_ci_jenkins_io.address_space
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["trustedcijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}
resource "azurerm_network_security_rule" "allow_in_https_from_trusted_to_acr" {
  name                    = "allow-in-https-from-vnet-to-acr"
  priority                = 4051
  direction               = "Inbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_virtual_network.trusted_ci_jenkins_io.address_space
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["trustedcijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

####################################################################################
## Public DNS records
####################################################################################
resource "azurerm_dns_a_record" "trusted_ci_controller" {
  name                = "@"
  zone_name           = module.trusted_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [module.trusted_ci_jenkins_io.controller_private_ipv4]
}

####################################################################################
## Private network resources (endpoint, DNS, etc.)
####################################################################################
resource "azurerm_private_dns_a_record" "updates_jenkins_io" {
  name                = "updates.jenkins.io" # Full expected record name: updates.jenkins.io.privatelink.azurecr.io
  zone_name           = azurerm_private_dns_zone.dockerhub_mirror["trustedcijenkinsio"].name
  resource_group_name = azurerm_private_dns_zone.dockerhub_mirror["trustedcijenkinsio"].resource_group_name
  ttl                 = 60
  records             = [azurerm_private_endpoint.publick8s_updates_jenkins_io_for_trustedci.private_service_connection[0].private_ip_address]
}

## updates.jenkins.io's mirrorbits CLI Kubernetes Service (internal LB)
data "azurerm_private_link_service" "publick8s_mirrorbitscli_updates_jenkins_io" {
  # TODO: track with updatecli from https://github.com/jenkins-infra/kubernetes-management/config/publick8s_updates-jenkins-io.yaml
  name                = "publick8s-updates.jenkins.io"
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
}
resource "azurerm_private_endpoint" "publick8s_updates_jenkins_io_for_trustedci" {
  name = "${data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.name}-for-trustedci"

  location            = var.location
  resource_group_name = data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.resource_group_name
  subnet_id           = data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.id

  custom_network_interface_name = "${data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.name}-for-trustedci-nic"

  private_service_connection {
    name                           = "${data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.name}-for-trustedci"
    private_connection_resource_id = data.azurerm_private_link_service.publick8s_mirrorbitscli_updates_jenkins_io.id
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = azurerm_private_dns_zone.dockerhub_mirror["trustedcijenkinsio"].name
    private_dns_zone_ids = [azurerm_private_dns_zone.dockerhub_mirror["trustedcijenkinsio"].id]
  }
  tags = local.default_tags
}
