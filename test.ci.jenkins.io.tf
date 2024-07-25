####################################################################################
## Resources for testing Azure VM Agents
####################################################################################
data "azurerm_resource_group" "test_azurevm_agents_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "jay-onboarding"
}

data "azurerm_virtual_network" "test_azurevm_agents_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "playground-vnet"
  resource_group_name = data.azurerm_resource_group.test_azurevm_agents_sponsorship.name
}

data "azurerm_subnet" "test_azurevm_agents_controller_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "default"
  resource_group_name  = data.azurerm_resource_group.test_azurevm_agents_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.test_azurevm_agents_sponsorship.name
}

data "azurerm_subnet" "test_azurevm_agents_agents_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "agents"
  resource_group_name  = data.azurerm_resource_group.test_azurevm_agents_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.test_azurevm_agents_sponsorship.name
}

####################################################################################
## Azure Active Directory Resources to allow controller spawning azure agents
####################################################################################
resource "azuread_application" "test_azurevm_agents_sponsorship" {
  display_name = "test.jay.onboarding"
  owners       = [data.azuread_service_principal.terraform_production.id]
  tags         = [for key, value in local.default_tags : "${key}:${value}"]
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  web {
    homepage_url = "http://test.jay.onboarding/"
  }
}
resource "azuread_service_principal" "test_azurevm_agents_sponsorship" {
  client_id                    = azuread_application.test_azurevm_agents_sponsorship.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_service_principal.terraform_production.id]
}
resource "azuread_application_password" "test_azurevm_agents_sponsorship" {
  application_id = azuread_application.test_azurevm_agents_sponsorship.id
  display_name   = "test.jay.onboarding-tf-managed"
  end_date       = "2024-08-31T00:00:00Z"
}
resource "azurerm_role_assignment" "controller_read_packer_prod_images" {
  scope                = azurerm_resource_group.packer_images["prod"].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.test_azurevm_agents_sponsorship.id
}
resource "azurerm_role_definition" "jayonboarding_vnet_reader" {
  name  = "Read-test.jay.onboarding-VNET"
  scope = data.azurerm_virtual_network.test_azurevm_agents_sponsorship.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "jayonboarding_vnet_reader" {
  scope              = data.azurerm_virtual_network.test_azurevm_agents_sponsorship.id
  role_definition_id = azurerm_role_definition.jayonboarding_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.test_azurevm_agents_sponsorship.id
}

module "test_azurevm_agents_sponsorship" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = "test.jay.onboarding"
  service_short_stripped_name      = "test-jay-onboarding"
  ephemeral_agents_network_rg_name = data.azurerm_subnet.test_azurevm_agents_agents_sponsorship.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.test_azurevm_agents_agents_sponsorship.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.test_azurevm_agents_agents_sponsorship.name
  controller_rg_name               = data.azurerm_resource_group.test_azurevm_agents_sponsorship.name
  controller_ips = compact([
    "135.237.163.64", # VM (manually managed) public IP
    "10.0.0.4",       # VM (manually managed) private IP
  ])
  controller_service_principal_id = azuread_service_principal.test_azurevm_agents_sponsorship.id
  default_tags                    = local.default_tags
  storage_account_name            = "jayagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}
