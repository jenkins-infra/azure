/** One resource group for the agents **/
resource "azurerm_resource_group" "infra_ci_jenkins_io_agents" {
  name     = "infra-agents"
  location = "East US 2"
}

/** Agent Resources **/
resource "azurerm_storage_account" "infra_ci_jenkins_io_agents" {
  name                     = "infraciagents"
  resource_group_name      = azurerm_resource_group.infra_ci_jenkins_io_agents.name
  location                 = azurerm_resource_group.infra_ci_jenkins_io_agents.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # default value, needed for tfsec
  tags                     = local.default_tags
}

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
  client_id                    = azuread_application.infra_ci_jenkins_io.client_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
}
resource "azuread_application_password" "infra_ci_jenkins_io" {
  application_id = azuread_application.infra_ci_jenkins_io.id
  display_name   = "infra.ci.jenkins.io-tf-managed"
  end_date       = "2024-03-22T00:00:00Z"
}
# Allow Service Principal to manage AzureRM resources inside the agents resource groups
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_azurerm" {
  scope                = azurerm_resource_group.infra_ci_jenkins_io_agents.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_packer" {
  scope                = azurerm_resource_group.packer_images["prod"].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_privatek8s_subnet_role" {
  scope                = data.azurerm_subnet.privatek8s_tier.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_privatek8s_subnet_private_vnet_reader" {
  scope              = data.azurerm_virtual_network.private.id
  role_definition_id = azurerm_role_definition.private_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_ci_jenkins_io.id
}

locals {
  infra_ci_jenkins_io_fqdn                        = "infra.ci.jenkins.io"
  infra_ci_jenkins_io_service_short_name          = trimprefix(trimprefix(local.infra_ci_jenkins_io_fqdn, "jenkins.io"), ".")
  infra_ci_jenkins_io_service_short_stripped_name = replace(local.infra_ci_jenkins_io_service_short_name, ".", "-")
}

## Sponsorship subscription specific resources for controller
data "azurerm_resource_group" "infra_ci_jenkins_io_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "infra-ci-jenkins-io-sponsorship"
}
data "azurerm_virtual_network" "infra_ci_jenkins_io_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "${data.azurerm_resource_group.infra_ci_jenkins_io_sponsorship.name}-vnet"
  resource_group_name = data.azurerm_resource_group.infra_ci_jenkins_io_sponsorship.name
}
data "azurerm_subnet" "infra_ci_jenkins_io_sponsorship_ephemeral_agents" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name}-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.resource_group_name
}
resource "azurerm_resource_group" "infra_ci_jenkins_io_controller_jenkins_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "infra-ci-jenkins-io-controller" # Custom name on the secondary subscription (it is AKS managed on the primary)
  location = var.location
  tags     = local.default_tags
}
# Required to allow controller to check for subnets inside the sponsorship network
resource "azurerm_role_definition" "infra_ci_jenkins_io_controller_vnet_sponsorship_reader" {
  provider = azurerm.jenkins-sponsorship
  name     = "Read-infra-ci-jenkins-io-sponsorship-VNET"
  scope    = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "infra_controller_vnet_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.id
  role_definition_id = azurerm_role_definition.infra_ci_jenkins_io_controller_vnet_sponsorship_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_ci_jenkins_io.id
}
module "infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = local.infra_ci_jenkins_io_fqdn
  service_short_stripped_name      = local.infra_ci_jenkins_io_service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.name
  controller_rg_name               = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  controller_ips                   = data.azurerm_subnet.privatek8s_tier.address_prefixes # Pod IPs: controller IP may change in the pods IP subnet
  controller_service_principal_id  = azuread_service_principal.infra_ci_jenkins_io.id
  default_tags                     = local.default_tags
  storage_account_name             = "infraciagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}
