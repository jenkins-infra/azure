# Network resources defined in https://github.com/jenkins-infra/azure-net
data "azurerm_resource_group" "trusted" {
  name = "trusted"
}
data "azurerm_virtual_network" "trusted" {
  name                = "${data.azurerm_resource_group.trusted.name}-vnet"
  resource_group_name = data.azurerm_resource_group.trusted.name
}
data "azurerm_subnet" "trusted_controller" {
  name                 = "${data.azurerm_virtual_network.trusted.name}-trusted-jenkins-ci-io-controller"
  virtual_network_name = data.azurerm_virtual_network.trusted.name
  resource_group_name  = data.azurerm_resource_group.trusted.name
}

resource "azurerm_resource_group" "trusted_ci_jenkins_io_agents" {
  name     = "jenkinsinfra-trustedvmagents"
  location = "East US"
}
resource "azurerm_resource_group" "trusted_ci_jenkins_io_controller" {
  name     = "jenkinsinfra-trusted-controller"
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
    subnet_id                     = data.azurerm_subnet.trusted_controller.id
  }
}
## MACHINE (bounce)
resource "azurerm_linux_virtual_machine" "trusted_bounce" {
  name                            = "trusted-bounce"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  size                            = "Standard_B1s"
  admin_username                  = local.trusted_ci_jenkins_io.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.trusted_bounce.id,
  ]

  admin_ssh_key {
    username   = local.trusted_ci_jenkins_io.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ=="
  }

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
## Network Security Groups for TRUSTED subnets
####################################################################################
# subnet trusted_controller
resource "azurerm_network_security_group" "trusted_controller" {
  name                = data.azurerm_subnet.trusted_controller.name
  location            = data.azurerm_resource_group.trusted.location
  resource_group_name = data.azurerm_resource_group.trusted.name

  # No security rule: using 'azurerm_network_security_rule' to allow composition across files

  tags = local.default_tags
}

resource "azurerm_subnet_network_security_group_association" "trusted_controller" {
  subnet_id                 = data.azurerm_subnet.trusted_controller.id
  network_security_group_id = azurerm_network_security_group.trusted_controller.id
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
  network_security_group_name  = azurerm_network_security_group.trusted_controller.name
}

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
  network_security_group_name = azurerm_network_security_group.trusted_controller.name
}
