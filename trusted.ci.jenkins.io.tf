resource "azurerm_private_dns_zone" "trusted" {
  name                = "trusted.ci.jenkins.io"
  resource_group_name = data.azurerm_resource_group.trusted_ci_jenkins_io.name
}
resource "azurerm_private_dns_zone_virtual_network_link" "trusted" {
  name                  = "trusted-vnet"
  resource_group_name   = data.azurerm_resource_group.trusted_ci_jenkins_io.name
  private_dns_zone_name = azurerm_private_dns_zone.trusted.name
  virtual_network_id    = data.azurerm_virtual_network.trusted_ci_jenkins_io.id
}
####################################################################################
## Resources for the Controller VM
####################################################################################
module "trusted_ci_jenkins_io" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-controller"

  providers = {
    azurerm     = azurerm
    azurerm.dns = azurerm
    azuread     = azuread
  }

  service_fqdn                 = azurerm_private_dns_zone.trusted.name
  location                     = data.azurerm_virtual_network.trusted_ci_jenkins_io.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ=="
  controller_network_name      = data.azurerm_virtual_network.trusted_ci_jenkins_io.name
  controller_network_rg_name   = data.azurerm_resource_group.trusted_ci_jenkins_io.name
  controller_subnet_name       = data.azurerm_subnet.trusted_ci_jenkins_io_controller.name
  controller_data_disk_size_gb = 128
  controller_vm_size           = "Standard_D2as_v5"
  default_tags                 = local.default_tags

  controller_resourcegroup_name = "jenkinsinfra-trusted-ci-controller"
  controller_datadisk_name      = "trusted-ci-controller-data-disk"

  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }

  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.id,
  ]
  controller_service_principal_end_date = "2024-11-20T00:00:00Z"
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images["prod"].id
  ]

  agent_ip_prefixes = concat(
    data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefixes,
    data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefixes,
    [azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address],
  )
}

module "trusted_ci_jenkins_io_azurevm_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  custom_resourcegroup_name        = "jenkinsinfra-trusted-ephemeral-agents"
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

# Required to allow azcopy sync of updates.jenkins.io File Share (content) with the permanent agent
module "trustedci_updatesjenkinsio_content_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn                   = "${module.trusted_ci_jenkins_io.service_fqdn}-fileshare_serviceprincipal_writer"
  active_directory_owners        = [data.azuread_service_principal.terraform_production.id]
  active_directory_url           = "https://github.com/jenkins-infra/azure"
  service_principal_end_date     = "2024-12-18T00:00:00Z"
  file_share_resource_manager_id = azurerm_storage_share.updates_jenkins_io_content.resource_manager_id
  storage_account_id             = azurerm_storage_account.updates_jenkins_io.id
  default_tags                   = local.default_tags
}
# Required to allow azcopy sync of updates.jenkins.io File Share (redirections) with the permanent agent
module "trustedci_updatesjenkinsio_redirects_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn                   = "${module.trusted_ci_jenkins_io.service_fqdn}-fileshare_serviceprincipal_writer-redirects"
  active_directory_owners        = [data.azuread_service_principal.terraform_production.id]
  active_directory_url           = "https://github.com/jenkins-infra/azure"
  service_principal_end_date     = "2024-12-18T00:00:00Z"
  file_share_resource_manager_id = azurerm_storage_share.updates_jenkins_io_redirects.resource_manager_id
  storage_account_id             = azurerm_storage_account.updates_jenkins_io.id
  default_tags                   = local.default_tags
}

# Required to allow azcopy sync of jenkins.io File Share
module "trustedci_jenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn                   = "trustedci-jenkinsio-fileshare_serviceprincipal_writer"
  active_directory_owners        = [data.azuread_service_principal.terraform_production.id]
  active_directory_url           = "https://github.com/jenkins-infra/azure"
  service_principal_end_date     = "2024-10-16T00:00:00Z"
  file_share_resource_manager_id = azurerm_storage_share.jenkins_io.resource_manager_id
  storage_account_id             = azurerm_storage_account.jenkins_io.id
  default_tags                   = local.default_tags
}

# Required to allow azcopy sync of javadoc.jenkins.io File Share
module "trustedci_javadocjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn                   = "trustedci-javadocjenkinsio-fileshare_serviceprincipal_writer"
  active_directory_owners        = [data.azuread_service_principal.terraform_production.id]
  active_directory_url           = "https://github.com/jenkins-infra/azure"
  service_principal_end_date     = "2024-10-16T00:00:00Z"
  file_share_resource_manager_id = azurerm_storage_share.javadoc_jenkins_io.resource_manager_id
  storage_account_id             = azurerm_storage_account.javadoc_jenkins_io.id
  default_tags                   = local.default_tags
}

## Sponsorship subscription specific resources for controller
resource "azurerm_resource_group" "trusted_ci_jenkins_io_controller_jenkins_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = module.trusted_ci_jenkins_io.controller_resourcegroup_name # Same name on both subscriptions
  location = var.location
  tags     = local.default_tags
}
# Required to allow controller to check for subnets inside the sponsorship network
resource "azurerm_role_definition" "trusted_ci_jenkins_io_controller_vnet_sponsorship_reader" {
  provider = azurerm.jenkins-sponsorship
  name     = "Read-trusted-ci-jenkins-io-sponsorship-VNET"
  scope    = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsorship.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "trusted_controller_vnet_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsorship.id
  role_definition_id = azurerm_role_definition.trusted_ci_jenkins_io_controller_vnet_sponsorship_reader.role_definition_resource_id
  principal_id       = module.trusted_ci_jenkins_io.controller_service_principal_id
}
module "trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsorship" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.trusted_ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.trusted_ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.name
  controller_rg_name               = azurerm_resource_group.trusted_ci_jenkins_io_controller_jenkins_sponsorship.name
  controller_ips                   = compact([module.trusted_ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.trusted_ci_jenkins_io.controller_service_principal_id
  default_tags                     = local.default_tags
  storage_account_name             = "trustedciagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

resource "azurerm_private_dns_a_record" "trusted_ci_controller" {
  name                = "@"
  zone_name           = azurerm_private_dns_zone.trusted.name
  resource_group_name = data.azurerm_resource_group.trusted_ci_jenkins_io.name
  ttl                 = 300
  records             = [module.trusted_ci_jenkins_io.controller_private_ipv4]
}

####################################################################################
## Resources for the bounce (SSH bastion) VM
####################################################################################
resource "azurerm_network_interface" "trusted_bounce" {
  name                = "bounce.${azurerm_private_dns_zone.trusted.name}"
  location            = data.azurerm_virtual_network.trusted_ci_jenkins_io.location
  resource_group_name = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  tags                = local.default_tags

  ip_configuration {
    name                          = "external"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = data.azurerm_subnet.trusted_ci_jenkins_io_controller.id
  }
}
resource "azurerm_linux_virtual_machine" "trusted_bounce" {
  name                            = "bounce.${azurerm_private_dns_zone.trusted.name}"
  resource_group_name             = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  location                        = data.azurerm_virtual_network.trusted_ci_jenkins_io.location
  size                            = "Standard_B1s"
  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.trusted_bounce.id,
  ]

  admin_ssh_key {
    username   = local.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ=="
  }

  user_data     = base64encode(templatefile("./.shared-tools/terraform/cloudinit.tftpl", { hostname = "bounce.${azurerm_private_dns_zone.trusted.name}" }))
  computer_name = "bounce.${azurerm_private_dns_zone.trusted.name}"

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # Use HDD (cheaper than SSD) as this machine does not need performances
    disk_size_gb         = 32             # Minimal size for ubuntu 22.04 image
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-minimal-jammy"
    sku       = "minimal-22_04-lts-gen2"
    version   = "latest"
  }
}

####################################################################################
## Resources for the permanent agent VM
####################################################################################
resource "azurerm_resource_group" "trusted_ci_jenkins_io_permanent_agents" {
  name     = "jenkinsinfra-trusted-permanent-agents"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_network_interface" "trusted_permanent_agent" {
  name                = "agent.${azurerm_private_dns_zone.trusted.name}"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_linux_virtual_machine" "trusted_permanent_agent" {
  name                            = "agent.${azurerm_private_dns_zone.trusted.name}"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.location
  tags                            = local.default_tags
  size                            = "Standard_D2as_v5"
  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.trusted_permanent_agent.id,
  ]

  admin_ssh_key {
    username   = local.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ== smerle@MacBook-Pro-de-Stephane.local"
  }

  user_data     = base64encode(templatefile("./.shared-tools/terraform/cloudinit.tftpl", { hostname = "agent.${azurerm_private_dns_zone.trusted.name}" }))
  computer_name = "agent.${azurerm_private_dns_zone.trusted.name}"

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = "128" # existing is 100GB, but as we will pay for 128GB, let's use it
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-minimal-jammy"
    sku       = "minimal-22_04-lts-gen2"
    version   = "latest"
  }
}
resource "azurerm_managed_disk" "trusted_permanent_agent_data_disk" {
  name                 = "trusted-permanent-agent-data-disk"
  location             = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.location
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "1024" # no intermediate between 512 and 1024

  tags = local.default_tags
}
resource "azurerm_virtual_machine_data_disk_attachment" "trusted_permanent_agent_data_disk" {
  managed_disk_id    = azurerm_managed_disk.trusted_permanent_agent_data_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.trusted_permanent_agent.id
  lun                = "20"
  caching            = "ReadWrite"
}
resource "azurerm_private_dns_a_record" "trusted_permanent_agent" {
  name                = "agent"
  zone_name           = azurerm_private_dns_zone.trusted.name
  resource_group_name = data.azurerm_resource_group.trusted_ci_jenkins_io.name
  ttl                 = 300
  records             = [azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address]
}

####################################################################################
## Network Security Group and rules
####################################################################################
resource "azurerm_subnet_network_security_group_association" "trusted_ci_permanent_agent" {
  subnet_id                 = data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.id
  network_security_group_id = module.trusted_ci_jenkins_io.controller_nsg_id
}

## Outbound Rules (different set of priorities than Inbound rules) ##
resource "azurerm_network_security_rule" "allow_out_https_from_trusted_ephemeral_agents_to_acr" {
  provider                = azurerm.jenkins-sponsorship
  name                    = "allow-out-https-from-ephemeral-agents-to-acr"
  priority                = 4050
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["trustedcijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = azurerm_resource_group.trusted_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}
# Ignore the rule as it does not detect the IP restriction to only update.jenkins.io"s host
#trivy:ignore:azure-network-no-public-egress
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_permanent_agent_to_updatecenter" {
  name                        = "allow-outbound-ssh-from-permanent-agent-to-updatecenter"
  priority                    = 4080
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address
  destination_address_prefix  = local.external_services["updates.${data.azurerm_dns_zone.jenkinsio.name}"]
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_outbound_from_bounce_to_controller" {
  name                        = "allow-outbound-from-bounce-to-controller"
  priority                    = 4090
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  destination_port_range      = "22"
  destination_address_prefix  = module.trusted_ci_jenkins_io.controller_private_ipv4
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_bounce_to_permanent_agent" {
  name                        = "allow-outbound-ssh-from-bounce-to-permanent-agent"
  priority                    = 4093
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  destination_address_prefix  = azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_bounce_to_ephemeral_agents" {
  name                        = "allow-outbound-ssh-from-bounce-to-ephemeral-agents"
  priority                    = 4094
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  destination_address_prefix  = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefix
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}

## Inbound Rules (different set of priorities than Outbound rules) ##
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_bounce_to_controller" {
  name                        = "allow-inbound-ssh-from-bounce-to-controller"
  priority                    = 3500
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  destination_address_prefix  = module.trusted_ci_jenkins_io.controller_private_ipv4
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_controller_to_permanent_agent" {
  name                        = "allow-inbound-ssh-from-controller-to-permanent-agent"
  priority                    = 3600
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = module.trusted_ci_jenkins_io.controller_private_ipv4
  destination_address_prefix  = azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_bounce_to_permanent_agent" {
  name                        = "allow-inbound-ssh-from-bounce-to-permanent-agent"
  priority                    = 3800
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  destination_address_prefix  = azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_bounce_to_ephemeral_agents" {
  name                        = "allow-inbound-ssh-from-bounce-to-ephemeral-agents"
  priority                    = 3900
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  destination_address_prefix  = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.address_prefix
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}
resource "azurerm_network_security_rule" "allow_in_https_from_trusted_ephemeral_agents_to_acr" {
  provider                = azurerm.jenkins-sponsorship
  name                    = "allow-in-https-from-ephemeral-agents-to-acr"
  priority                = 4050
  direction               = "Inbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["trustedcijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = azurerm_resource_group.trusted_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}
#trivy:ignore:azure-network-no-public-ingress
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_internet_to_bounce" {
  name                        = "allow-inbound-ssh-from-internet-to-bounce"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  destination_address_prefix  = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}

####################################################################################
## Public DNS records
####################################################################################
resource "azurerm_dns_a_record" "trusted_bounce" {
  name                = "bounce"
  zone_name           = data.azurerm_dns_zone.trusted_ci_jenkins_io.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_linux_virtual_machine.trusted_bounce.private_ip_address]
  tags                = local.default_tags
}

####################################################################################
## Private endpoints
####################################################################################
## updates.jenkins.io's mirrorbits CLI Kubernetes Service (internal LB)
data "azurerm_private_link_service" "updates_jenkins_io_cli" {
  # https://github.com/jenkins-infra/kubernetes-management/blob/67e5741bf926c72c143604301132cbe6ada0bab8/config/updates.jenkins.io.yaml#L126
  name                = "updates.jenkins.io-cli"
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
}

resource "azurerm_private_endpoint" "updates_jio_mirrorbits_cli_for_trustedci" {
  name = "${data.azurerm_private_link_service.updates_jenkins_io_cli.name}-for-trustedci"

  location            = var.location
  resource_group_name = data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.resource_group_name
  subnet_id           = data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.id

  custom_network_interface_name = "${data.azurerm_private_link_service.updates_jenkins_io_cli.name}-for-trustedci-nic"

  private_service_connection {
    name                           = "${data.azurerm_private_link_service.updates_jenkins_io_cli.name}-for-trustedci"
    private_connection_resource_id = data.azurerm_private_link_service.updates_jenkins_io_cli.id
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "trusted.ci.jenkins.io"
    private_dns_zone_ids = [azurerm_private_dns_zone.trusted.id]
  }
  tags = local.default_tags
}

resource "azurerm_private_dns_a_record" "updates_jio_mirrorbits_cli_for_trustedci" {
  name                = "updates.jio-cli"
  zone_name           = azurerm_private_dns_zone.trusted.name
  resource_group_name = data.azurerm_resource_group.trusted_ci_jenkins_io.name
  ttl                 = 60
  records             = [azurerm_private_endpoint.updates_jio_mirrorbits_cli_for_trustedci.private_service_connection[0].private_ip_address]
}
