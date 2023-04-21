####################################################################################
## TRUSTED NETWORK Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
####################################################################################
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
data "azurerm_subnet" "trusted_vmagents" {
  name                 = "${data.azurerm_virtual_network.trusted.name}-trusted-jenkins-ci-io-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.trusted.name
  resource_group_name  = data.azurerm_resource_group.trusted.name
}
data "azurerm_subnet" "trusted_permanent_agents" {
  name                 = "${data.azurerm_virtual_network.trusted.name}-trusted-jenkins-ci-io-permanent-agents"
  virtual_network_name = data.azurerm_virtual_network.trusted.name
  resource_group_name  = data.azurerm_resource_group.trusted.name
}

####################################################################################
## TRUSTED RESOURCES
####################################################################################
# Resources groups for TRUSTED Agents
resource "azurerm_resource_group" "trusted_ci_jenkins_io_agents" {
  name     = "jenkinsinfra-trustedvmagents"
  location = "East US"
}
resource "azurerm_resource_group" "trusted_ci_jenkins_io_permanent_agents" {
  name     = "jenkinsinfra-trusted-permanent-vmagents"
  location = "East US"
}
resource "azurerm_resource_group" "trusted_ci_jenkins_io_controller" {
  name     = "jenkinsinfra-trusted-controller"
  location = "East US"
}

#APPLICATION azureAD
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

#SERVICE PRINCIPAL azureAD
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

############################# VMs ####################################

# NETWORKING FROM azure-net repository
# check in vnets.tf
#

# CONTROLLER VM
## NETWORK INTERFACE with internal ip
resource "azurerm_network_interface" "trusted_controller" {
  name                = "trusted-controller-nic"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.trusted_controller.id
    private_ip_address_allocation = "Dynamic"
  }
}

## MACHINE (controller)
resource "azurerm_linux_virtual_machine" "trusted_controller" {
  name                            = "trusted-controller"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  tags                            = local.default_tags
  size                            = "Standard_D2as_v5"
  admin_username                  = "adminuser"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.trusted_controller.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ== smerle@MacBook-Pro-de-Stephane.local"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22.04-LTS"
    version   = "latest"
  }
}

resource "azurerm_managed_disk" "trusted_controller_data_disk" {
  name                 = "trusted-controller-data-disk"
  location             = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "100"

  tags                 = local.default_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "trusted_controller_data_disk" {
  managed_disk_id    = azurerm_managed_disk.trusted_controller_data_disk.id
  virtual_machine_id = azurerm_virtual_machine.trusted_controller.id
  lun                = "10"
  caching            = "ReadWrite"
}

# BOUNCE VM
## PUBLIC IP
resource "azurerm_public_ip" "trusted_bounce" {
  name                = "trusted-bounce-external-ip"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  allocation_method   = "Static"
  tags                = local.default_tags
}
## NETWORK INTERFACE with public ip and internal ip
resource "azurerm_network_interface" "trusted_bounce" {
  name                = "trusted-bounce-internal-nic"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.trusted_controller.id
    private_ip_address_allocation = "Dynamic"
  }
  ip_configuration {
    name                          = "external"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.trusted_bounce.id
    primary                       = true
  }
}
## MACHINE (bounce)
resource "azurerm_linux_virtual_machine" "trusted_bounce" {
  name                            = "trusted-bounce"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  size                            = "Standard_F1"
  admin_username                  = "adminuser"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.trusted_bounce.id,
  ]

  //TODO (check with ddu) add all public ssh keys used today to access the controller
  admin_ssh_key {
    username   = "adminuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC5K7Ro7jBl5Kc68RdzG6EXHstIBFSxO5Da8SQJSMeCbb4cHTYuBBH8jNsAFcnkN64kEu+YhmlxaWEVEIrPgfGfs13ZL7v9p+Nt76tsz6gnVdAy2zCz607pAWe7p4bBn6T9zdZcBSnvjawO+8t/5ue4ngcfAjanN5OsOgLeD6yqVyP8YTERjW78jvp2TFrIYmgWMI5ES1ln32PQmRZwc1eAOsyGJW/YIBdOxaSkZ41qUvb9b3dCorGuCovpSK2EeNphjLPpVX/NRpVY4YlDqAcTCdLdDrEeVqkiA/VDCYNhudZTDa8f1iHwBE/GEtlKmoO6dxJ5LAkRk3RIVHYrmI6XXSw5l0tHhW5D12MNwzUfDxQEzBpGK5iSfOBt5zJ5OiI9ftnsq/GV7vCXfvMVGDLUC551P5/s/wM70QmHwhlGQNLNeJxRTvd6tL11bof3K+29ivFYUmpU17iVxYOWhkNY86WyngHU6Ux0zaczF3H6H0tpg1Ca/cFO428AVPw/RTJpcAe6OVKq5zwARNApQ/p6fJKUAdXap+PpQGZlQhPLkUbwtFXGTrpX9ePTcdzryCYjgrZouvy4ZMzruJiIbFUH8mRY3xVREVaIsJakruvgw3b14oQgcB4BwYVBBqi62xIvbRzAv7Su9t2jK6OR2z3sM/hLJRqIJ5oILMORa7XqrQ== smerle@MacBook-Pro-de-Stephane.local"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22.04-LTS"
    version   = "latest"
  }
}
