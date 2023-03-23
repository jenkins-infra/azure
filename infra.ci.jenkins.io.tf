/** One resource group for the agents **/
resource "azurerm_resource_group" "infra_ci_jenkins_io_agents" {
  name     = "infra-agents"
  location = "East US 2"
}

/** Agent Resources **/
// TODO: create a storage account
// TODO: create a virtual network/subnet for the agent VM

# Azure AD resources to allow controller to spawn agents in Azure
resource "azuread_application" "infra_ci_jenkins_io" {
  display_name = "infra.ci.jenkins.io"
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
resource "azuread_service_principal" "infra_ci_jenkins_io" {
  application_id               = azuread_application.infra_ci_jenkins_io.application_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
}
resource "azuread_application_password" "infra_ci_jenkins_io" {
  application_object_id = azuread_application.infra_ci_jenkins_io.object_id
  display_name          = "infra.ci.jenkins.io-tf-managed"
  end_date              = "2024-03-22T00:00:00Z"
}
# Allow Service Principal to manage AzureRM resources inside the agents resource groups
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_azurerm" {
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${azurerm_resource_group.infra_ci_jenkins_io_agents.name}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_packer" {
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/prod-packer-images"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_privatek8s_subnet_networkcontributor" {
  scope                = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private.name}/subnets/${data.azurerm_subnet.privatek8s_tier.name}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.id
}

resource "azurerm_role_definition" "private_vnet_reader" {
  name  = "PrivateVNET"
  scope = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private.name}}"

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_privatek8s_subnet_private_vnet_reader" {
  scope              = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private.name}}"
  role_definition_id = azurerm_role_definition.private_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_ci_jenkins_io.id
}
