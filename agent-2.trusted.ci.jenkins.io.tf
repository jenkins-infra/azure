####################################################################################
## Resources for the permanent agent VM
####################################################################################
resource "azurerm_resource_group" "trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored" {
  provider = azurerm.jenkins-sponsored
  name     = "trusted-ci-jenkins-io-sponsored-permanent-agents"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_network_interface" "agent_2_trusted_ci_jenkins_io_jenkins_sponsored" {
  provider            = azurerm.jenkins-sponsored
  name                = "agent-2-trusted-ci-jenkins-io"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_linux_virtual_machine" "agent_2_trusted_ci_jenkins_io_jenkins_sponsored" {
  provider                        = azurerm.jenkins-sponsored
  name                            = "agent-2.trusted.ci.jenkins.io"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.location
  tags                            = local.default_tags
  size                            = "Standard_D2s_v3" # 2 vCPU 8Go RAM
  admin_username                  = local.admin_username
  zone                            = "1" # We need a zonale deployment to attach a Premium_SSD_v2 data disk
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.agent_2_trusted_ci_jenkins_io_jenkins_sponsored.id,
  ]

  admin_ssh_key {
    username   = local.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ== smerle@MacBook-Pro-de-Stephane.local"
  }

  user_data = base64encode(
    templatefile("./.shared-tools/terraform/cloudinit.tftpl", {
      hostname       = "agent-2.trusted.ci.jenkins.io",
      admin_username = local.admin_username,
      }
  ))
  computer_name = "agent-2.trusted.ci.jenkins.io"

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = "32" # Minimum size with Ubuntu base image
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-minimal-jammy"
    sku       = "minimal-22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins.id,
      azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored.id,
    ]
  }
}
resource "azurerm_managed_disk" "agent_2_trusted_ci_jenkins_io_data_jenkins_sponsored" {
  provider             = azurerm.jenkins-sponsored
  name                 = "agent-2-trusted-ci-jenkins-io-data"
  location             = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.location
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.name
  zone                 = azurerm_linux_virtual_machine.agent_2_trusted_ci_jenkins_io_jenkins_sponsored.zone
  storage_account_type = "PremiumV2_LRS"
  create_option        = "Empty"
  disk_size_gb         = "580"

  tags = local.default_tags
}
resource "azurerm_virtual_machine_data_disk_attachment" "agent_2_trusted_ci_jenkins_io_data_jenkins_sponsored" {
  provider           = azurerm.jenkins-sponsored
  managed_disk_id    = azurerm_managed_disk.agent_2_trusted_ci_jenkins_io_data_jenkins_sponsored.id
  virtual_machine_id = azurerm_linux_virtual_machine.agent_2_trusted_ci_jenkins_io_jenkins_sponsored.id
  lun                = "20"
  caching            = "None" # Caching not supported with "PremiumV2_LRS"
}

####################################################################################
## Network Security Group and rules
####################################################################################
resource "azurerm_subnet_network_security_group_association" "trusted_ci_permanent_agent_2_jenkins_sponsored" {
  provider                  = azurerm.jenkins-sponsored
  subnet_id                 = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_permanent_agents.id
  network_security_group_id = module.trusted_ci_jenkins_io.controller_nsg_id
}

resource "azurerm_network_security_rule" "allow_inbound_ssh_from_controller_to_permanent_agent_2_jenkins_sponsored" {
  provider               = azurerm.jenkins-sponsored
  name                   = "allow-inbound-ssh-from-controller-to-permanent-agent-2"
  priority               = 3600
  direction              = "Inbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "22"
  source_address_prefix  = module.trusted_ci_jenkins_io.controller_private_ipv4
  destination_address_prefixes = [
    azurerm_linux_virtual_machine.agent_2_trusted_ci_jenkins_io_jenkins_sponsored.private_ip_address,
  ]
  resource_group_name         = module.trusted_ci_jenkins_io.controller_resourcegroup_name
  network_security_group_name = module.trusted_ci_jenkins_io.controller_nsg_name
}

####################################################################################
## Public DNS records
####################################################################################
resource "azurerm_dns_a_record" "trusted_permanent_agent_2" {
  name                = "agent-2"
  zone_name           = module.trusted_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_linux_virtual_machine.agent_2_trusted_ci_jenkins_io_jenkins_sponsored.private_ip_address]
}
