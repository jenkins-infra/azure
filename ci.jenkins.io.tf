/** Two resources groups: one for the controller, the second for the agents **/
resource "azurerm_resource_group" "ci_jenkins_io_controller" {
  name     = "ci-jenkins-io-controller"
  location = "East US 2"
  
  tags = local.default_tags
}

resource "azurerm_resource_group" "ci_jenkins_io_agents" {
  name     = "eastus-cijenkinsio"
  location = "East US"
}

/** Controller Resources **/
# Defined in https://github.com/jenkins-infra/azure-net/blob/d30a37c27b649aebd158ecb5d631ff8d7f1bab4e/vnets.tf#L175-L183
data "azurerm_subnet" "ci_jenkins_io_controller" {
  name                 = "${data.azurerm_virtual_network.public.name}-ci_jenkins_io_controller"
  virtual_network_name = data.azurerm_virtual_network.public.name
  resource_group_name  = data.azurerm_resource_group.public.name
}
resource "azurerm_public_ip" "ci_jenkins_io" {
  name                = "ci-jenkins-io"
  location            = azurerm_resource_group.ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.ci_jenkins_io_controller.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}
resource "azurerm_network_interface" "ci_jenkins_io" {
  name                = "ci-jenkins-io"
  location            = azurerm_resource_group.ci_jenkins_io_controller.location
  resource_group_name = azurerm_resource_group.ci_jenkins_io_controller.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "external"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ci_jenkins_io.id
    subnet_id                     = data.azurerm_subnet.ci_jenkins_io_controller.id
  }
}
resource "azurerm_managed_disk" "ci_jenkins_io_data" {
  name                 = "ci-jenkins-io-data"
  location             = azurerm_resource_group.ci_jenkins_io_controller.location
  resource_group_name  = azurerm_resource_group.ci_jenkins_io_controller.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = "512"

  tags = local.default_tags
}
resource "azurerm_linux_virtual_machine" "ci_jenkins_io" {
  name                            = "ci-jenkins-io"
  resource_group_name             = azurerm_resource_group.ci_jenkins_io_controller.name
  location                        = azurerm_resource_group.ci_jenkins_io_controller.location
  tags                            = local.default_tags
  size                            = "Standard_D8as_v5"
  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.ci_jenkins_io.id,
  ]

  admin_ssh_key {
    username   = local.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKvZ23dkvhjSU0Gxl5+mKcBOwmR7gqJDYeA1/Xzl3otV4CtC5te5Vx7YnNEFDXD6BsNkFaliXa34yE37WMdWl+exIURBMhBLmOPxEP/cWA5ZbXP//78ejZsxawBpBJy27uQhdcR0zVoMJc8Q9ShYl5YT/Tq1UcPq2wTNFvnrBJL1FrpGT+6l46BTHI+Wpso8BK64LsfX3hKnJEGuHSM0GAcYQSpXAeGS9zObKyZpk3of/Qw/2sVilIOAgNODbwqyWgEBTjMUln71Mjlt1hsEkv3K/VdvpFNF8VNq5k94VX6Rvg5FQBRL5IrlkuNwGWcBbl8Ydqk4wrD3b/PrtuLBEUsqbNhLnlEvFcjak+u2kzCov73csN/oylR0Tkr2y9x2HfZgDJVtvKjkkc4QERo7AqlTuy1whGfDYsioeabVLjZ9ahPjakv9qwcBrEEF+pAya7Q3AgNFVSdPgLDEwEO8GUHaxAjtyXXv9+yPdoDGmG3Pfn3KqM6UZjHCxne3Dr5ZE="
  }

  user_data     = base64encode(templatefile("./.shared-tools/terraform/cloudinit.tftpl", { hostname = "ci.jenkins.io" }))
  computer_name = "ci-jenkins-io"

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64 # Minimal size for ubuntu 22.04 image
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-minimal-jammy"
    sku       = "minimal-22_04-lts-gen2"
    version   = "latest"
  }
}
resource "azurerm_virtual_machine_data_disk_attachment" "ci_jenkins_io_data" {
  managed_disk_id    = azurerm_managed_disk.ci_jenkins_io_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.ci_jenkins_io.id
  lun                = "10"
  caching            = "ReadWrite"
}

/** Agent Resources **/
resource "azurerm_storage_account" "ci_jenkins_io_agents" {
  name                     = "cijenkinsiovmagents"
  resource_group_name      = azurerm_resource_group.ci_jenkins_io_agents.name
  location                 = azurerm_resource_group.ci_jenkins_io_agents.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # default value, needed for tfsec
  tags                     = local.default_tags
}

# Azure AD resources to allow controller to spawn agents in Azure
resource "azuread_application" "ci_jenkins_io" {
  display_name = "ci.jenkins.io"
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
resource "azuread_service_principal" "ci_jenkins_io" {
  application_id               = azuread_application.ci_jenkins_io.application_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
}
resource "azuread_application_password" "ci_jenkins_io" {
  application_object_id = azuread_application.ci_jenkins_io.object_id
  display_name          = "ci.jenkins.io-tf-managed"
  end_date              = "2024-03-28T00:00:00Z"
}

# Allow application to manage AzureRM resources inside the agents resource groups
resource "azurerm_role_assignment" "ci_jenkins_io_contributor_in_agent_resourcegroup" {
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${azurerm_resource_group.ci_jenkins_io_agents.name}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.ci_jenkins_io.id
}
resource "azurerm_role_assignment" "ci_jenkins_io_read_packer_prod_images" {
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${azurerm_resource_group.packer_images["prod"].name}"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.ci_jenkins_io.id
}
# Allow application to create/delete VM network interfaces in this subnet
resource "azurerm_role_assignment" "ci_jenkins_io_manage_net_interfaces_subnet_ci_agents" {
  // TODO: manage this subnet in jenkins-infra/azure-net along with a security group
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/prod-jenkins-public-prod/providers/Microsoft.Network/virtualNetworks/prod-jenkins-public-prod/subnets/ci.j-agents-vm"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_service_principal.ci_jenkins_io.id
}
resource "azurerm_role_assignment" "ci_jenkins_io_read_public_vnets" {
  scope              = "${data.azurerm_subscription.jenkins.id}/resourceGroups/prod-jenkins-public-prod/providers/Microsoft.Network/virtualNetworks/prod-jenkins-public-prod"
  role_definition_id = azurerm_role_definition.prod_public_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.ci_jenkins_io.id
}
