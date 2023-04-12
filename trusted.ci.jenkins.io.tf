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
# TODO lower this scope to the resource group
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



############################# VMS ####################################

# NETWORKING TO BE MOVED TO azure-net repository
resource "azurerm_virtual_network" "trusted" {
  name                = "trusted-controller-network"
  address_space       = ["10.0.0.0/24"]
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  tags                = local.default_tags
}
### Trusted VNet Address Plan:
# TO BE COMPLETED
resource "azurerm_subnet" "trusted_controller" {
  name                 = "trusted-controller-subnet"
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  virtual_network_name = azurerm_virtual_network.trusted.name
  address_prefixes     = ["10.0.1.0/24"]
}
resource "azurerm_subnet" "trusted_vmagents" {
  name                 = "trusted-vmagents-subnet"
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_agents.name
  virtual_network_name = azurerm_virtual_network.trusted.name
  address_prefixes     = ["10.0.2.0/24"]
}
resource "azurerm_subnet" "trusted_permanent_agents" {
  name                 = "trusted-permanent-agents-subnet"
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents.name
  virtual_network_name = azurerm_virtual_network.trusted.name
  address_prefixes     = ["10.0.3.0/24"]
}


resource "azurerm_network_security_group" "trusted_bounce" {
  name                = "TrustedBounceSecurityGroup"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
}

resource "azurerm_network_security_rule" "trusted_bounce_inbound" {
  name                        = "bounce-rule-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "10.0.1.0/24"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  network_security_group_name = azurerm_network_security_group.trusted_bounce.name
}

resource "azurerm_network_security_rule" "trusted_bounce_outbound" {
  name                        = "bounce-rule-outbound"
  priority                    = 101
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  network_security_group_name = azurerm_network_security_group.trusted_bounce.name
}

resource "azurerm_network_interface" "trusted_controller" {
  name                = "trusted-controller-nic"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.trusted_controller.id
    private_ip_address_allocation = "Dynamic"
  }
}

/*
  NOT SURE ABOUT THIS as
  The private key generated by this resource will be stored unencrypted in your Terraform state file. Use of this resource for production deployments is not recommended. Instead, generate a private key file outside of Terraform and distribute it securely to the system where Terraform will be run.
*/
resource "tls_private_key" "trusted_controller" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


resource "azurerm_linux_virtual_machine" "trusted_controller" {
  name                            = "trusted-controller"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  tags                            = local.default_tags
  size                            = "Standard_F2"
  admin_username                  = "adminuser"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.trusted_controller.id,
  ]

  //TODO (check with ddu) add all public ssh keys used today to access the controller
  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.trusted_controller.public_key_openssh
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

resource "azurerm_public_ip" "trusted_bounce" {
  name                = "trusted-bounce-external-ip"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  allocation_method   = "Static"
  tags                = local.default_tags
}

resource "azurerm_network_interface" "trusted_bounce" {
  name                = "trusted-bounce-internal-nic"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_controller.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.trusted_controller.id
    private_ip_address_allocation = "Dynamic"
  }
  ip_configuration {
    name                          = "external"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.trusted_bounce.id
    primary                       = true
  }
}
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
    public_key = tls_private_key.trusted_controller.public_key_openssh
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
