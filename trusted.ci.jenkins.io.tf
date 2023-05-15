# Network resources defined in https://github.com/jenkins-infra/azure-net
data "azurerm_resource_group" "trusted" {
  name = "trusted"
}
data "azurerm_virtual_network" "trusted" {
  name                = "${data.azurerm_resource_group.trusted.name}-vnet"
  resource_group_name = data.azurerm_resource_group.trusted.name
}
data "azurerm_subnet" "trusted_ci_controller" {
  name                 = "${data.azurerm_virtual_network.trusted.name}-trusted-jenkins-ci-io-controller"
  virtual_network_name = data.azurerm_virtual_network.trusted.name
  resource_group_name  = data.azurerm_resource_group.trusted.name
}
data "azurerm_subnet" "trusted_permanent_agents" {
  name                 = "${data.azurerm_virtual_network.trusted.name}-trusted-jenkins-ci-io-permanent-agents"
  virtual_network_name = data.azurerm_virtual_network.trusted.name
  resource_group_name  = data.azurerm_resource_group.trusted.name
}
data "azurerm_subnet" "trusted_ephemeral_agents" {
  name                 = "${data.azurerm_virtual_network.trusted.name}-trusted-jenkins-ci-io-ephemeral-agents"
  resource_group_name  = data.azurerm_resource_group.trusted.name
  virtual_network_name = data.azurerm_virtual_network.trusted.name
}
resource "azurerm_resource_group" "trusted_ci_jenkins_io_agents" {
  name     = "jenkinsinfra-trustedvmagents"
  location = "East US"
}
resource "azurerm_resource_group" "trusted_ci_jenkins_io_controller" {
  name     = "jenkinsinfra-trusted-ci-controller"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_resource_group" "trusted_ci_jenkins_io_permanent_agents" {
  name     = "jenkinsinfra-trusted-permanent-agents"
  location = var.location
  tags     = local.default_tags
}
resource "azuread_application" "trusted_ci_jenkins_io" {
  display_name = "trusted.ci.jenkins.io"
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

resource "azuread_service_principal" "trusted_ci_jenkins_io" {
  application_id               = azuread_application.trusted_ci_jenkins_io.application_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
}

resource "azuread_application_password" "trusted_ci_jenkins_io" {
  application_object_id = azuread_application.trusted_ci_jenkins_io.object_id
  display_name          = "trusted.ci.jenkins.io-tf-managed"
  end_date              = "2024-03-08T19:40:35Z"
}

# Allow Service Principal to manage AzureRM resources inside the subscription
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_allow_azurerm" {
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${azurerm_resource_group.trusted_ci_jenkins_io_agents.name}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.trusted_ci_jenkins_io.id
}

resource "azurerm_role_assignment" "trusted_ci_jenkins_io_allow_packer" {
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/prod-packer-images"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.trusted_ci_jenkins_io.id
}

# DNS
resource "azurerm_private_dns_zone" "trusted" {
  name                = "trusted.ci.jenkins.io"
  resource_group_name = data.azurerm_resource_group.trusted.name
}
resource "azurerm_private_dns_zone_virtual_network_link" "trusted" {
  name                  = "trusted-vnet"
  resource_group_name   = data.azurerm_resource_group.trusted.name
  private_dns_zone_name = azurerm_private_dns_zone.trusted.name
  virtual_network_id    = data.azurerm_virtual_network.trusted.id
}

# VMs
# BOUNCE VM
resource "azurerm_public_ip" "trusted_bounce" {
  name                = "trusted-bounce"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}
## NETWORK INTERFACE with public ip and internal ip
resource "azurerm_network_interface" "trusted_bounce" {
  name                = "trusted-bounce"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "external"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.trusted_bounce.id
    subnet_id                     = data.azurerm_subnet.trusted_ci_controller.id
  }
}
## MACHINE (bounce)
resource "azurerm_linux_virtual_machine" "trusted_bounce" {
  name                            = "trusted-bounce"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
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

  # Use cloud-init to configure the VM
  user_data     = base64encode(templatefile("./.shared-tools/terraform/cloudinit.tftpl", { hostname = "bounce.trusted.ci.jenkins.io" }))
  computer_name = "bounce-trusted-ci-jenkins-io"

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

# CONTROLLER VM
## NETWORK INTERFACE with internal ip
resource "azurerm_network_interface" "trusted_ci_controller" {
  name                = "trusted-ci-controller"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.trusted_ci_controller.id
    private_ip_address_allocation = "Dynamic"
  }
}

## MACHINE (controller)
resource "azurerm_linux_virtual_machine" "trusted_ci_controller" {
  name                            = "trusted-ci-controller"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  tags                            = local.default_tags
  size                            = "Standard_D2as_v5"
  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.trusted_ci_controller.id,
  ]

  admin_ssh_key {
    username   = local.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ=="
  }

  # Use cloud-init to configure the VM
  user_data = base64encode(templatefile("./.shared-tools/terraform/cloudinit.tftpl", { hostname = "trusted.ci.jenkins.io" }))
  # Force VM recreation when the VPN URL change
  computer_name = "trusted-ci-jenkins-io"

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 32 # Minimal size for ubuntu 22.04 image
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-minimal-jammy"
    sku       = "minimal-22_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_managed_disk" "trusted_ci_controller_data_disk" {
  name                 = "trusted-ci-controller-data-disk"
  location             = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = "128"

  tags = local.default_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "trusted_ci_controller_data_disk" {
  managed_disk_id    = azurerm_managed_disk.trusted_ci_controller_data_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.trusted_ci_controller.id
  lun                = "10"
  caching            = "ReadWrite"
}

resource "azurerm_private_dns_a_record" "trusted_ci_controller" {
  name                = "@"
  zone_name           = azurerm_private_dns_zone.trusted.name
  resource_group_name = data.azurerm_resource_group.trusted.name
  ttl                 = 300
  records             = [azurerm_linux_virtual_machine.trusted_ci_controller.private_ip_address]
}

# PERMANENT AGENT VM
## NETWORK INTERFACE with internal ip
resource "azurerm_network_interface" "trusted_permanent_agent" {
  name                = "trusted-permanent-agent"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.trusted_permanent_agents.id
    private_ip_address_allocation = "Dynamic"
  }
}

## MACHINE (permanent agent)
resource "azurerm_linux_virtual_machine" "trusted_permanent_agent" {
  name                            = "trusted-permanent-agent"
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

  # Use cloud-init to configure the VM
  user_data = base64encode(templatefile("./.shared-tools/terraform/cloudinit.tftpl", { hostname = "agent.trusted.ci.jenkins.io" }))
  # Force VM recreation when the VPN URL change
  computer_name = "agent-trusted-ci-jenkins-io"

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
  name                = "permanent.agent"
  zone_name           = azurerm_private_dns_zone.trusted.name
  resource_group_name = data.azurerm_resource_group.trusted.name
  ttl                 = 300
  records             = [azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address]
}

####################################################################################
## Network Security Groups for TRUSTED subnets
####################################################################################
# subnet trusted_ci_controller
resource "azurerm_network_security_group" "trusted_ci_controller" {
  name                = data.azurerm_subnet.trusted_ci_controller.name
  location            = data.azurerm_resource_group.trusted.location
  resource_group_name = data.azurerm_resource_group.trusted.name

  # No security rule: using 'azurerm_network_security_rule' to allow composition across files

  tags = local.default_tags
}

resource "azurerm_subnet_network_security_group_association" "trusted_ci_controller" {
  subnet_id                 = data.azurerm_subnet.trusted_ci_controller.id
  network_security_group_id = azurerm_network_security_group.trusted_ci_controller.id
}

resource "azurerm_network_security_rule" "deny_all_to_vnet" {
  name = "deny-all-to-vnet"
  # Priority should be the highest value possible (lower than the default 65000 "default" rules not overidable) but higher than the other security rules
  # ref. https://github.com/hashicorp/terraform-provider-azurerm/issues/11137 and https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule#priority
  priority                     = 4095
  direction                    = "Outbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "*"
  destination_address_prefixes = data.azurerm_virtual_network.trusted.address_space
  resource_group_name          = data.azurerm_resource_group.trusted.name
  network_security_group_name  = azurerm_network_security_group.trusted_ci_controller.name
}

# TODO: add all ips from people needing access to trusted.ci.jenkins.io, or remove the rule at final migration. (Cf https://github.com/jenkins-infra/azure/pull/334#discussion_r1179955821)
resource "azurerm_network_security_rule" "allow_ssh_from_admins_to_bounce" {
  for_each = local.admin_allowed_ips

  name                        = "allow-22-from-${each.key}-to-bounce"
  priority                    = 4000 + index(keys(local.admin_allowed_ips), each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.value
  destination_address_prefix  = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  resource_group_name         = data.azurerm_resource_group.trusted.name
  network_security_group_name = azurerm_network_security_group.trusted_ci_controller.name
}

resource "azurerm_network_security_rule" "allow_ssh_from_bounce_to_controller" {
  name                        = "allow-22-from-bounce-to-controller"
  priority                    = 3500
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "22"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_bounce.private_ip_address
  destination_address_prefix  = azurerm_linux_virtual_machine.trusted_ci_controller.private_ip_address
  resource_group_name         = data.azurerm_resource_group.trusted.name
  network_security_group_name = azurerm_network_security_group.trusted_ci_controller.name
}

resource "azurerm_network_security_rule" "allow_ssh_from_controller_to_permanent_agent" {
  name                        = "allow-22-from-controller-to-permanent-agent"
  priority                    = 3600
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "22"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_ci_controller.private_ip_address
  destination_address_prefix  = azurerm_linux_virtual_machine.trusted_permanent_agent.private_ip_address
  resource_group_name         = data.azurerm_resource_group.trusted.name
  network_security_group_name = azurerm_network_security_group.trusted_ci_controller.name
}

resource "azurerm_network_security_rule" "allow_ssh_from_controller_to_ephemeral_agents" {
  name                        = "allow-22-from-controller-to-ephemeral-agents"
  priority                    = 3700
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "22"
  destination_port_range      = "22"
  source_address_prefix       = azurerm_linux_virtual_machine.trusted_ci_controller.private_ip_address
  destination_address_prefix  = data.azurerm_subnet.trusted_ephemeral_agents.address_prefix
  resource_group_name         = data.azurerm_resource_group.trusted.name
  network_security_group_name = azurerm_network_security_group.trusted_ci_controller.name
}
