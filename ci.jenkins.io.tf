/** Two resources groups: one for the controller, the second for the agents **/
# resource "azurerm_resource_group" "ci_jenkins_io_controller" {
#   name     = "prodjenkinsci"
#   location = "East US 2"
# }

resource "azurerm_resource_group" "ci_jenkins_io_agents" {
  name     = "eastus-cijenkinsio"
  location = "East US"
}

/** Controller Resources **/

// TODO: import prodci public IP address
// TODO: import prod-ci network interface
// TODO: import ci-data disk
// TODO: import prodci system disk
// TODO: import prod-ci VM
// TODO: import prodjenkinscistore storage account (used for boot diagnostics)

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
  scope = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.public.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.public.name}/subnets/ci.j-agents-vm"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_service_principal.ci_jenkins_io.id
}
resource "azurerm_role_assignment" "ci_jenkins_io_read_public_vnets" {
  scope              = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.public.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.public.name}"
  role_definition_id = azurerm_role_definition.public_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.ci_jenkins_io.id
}
