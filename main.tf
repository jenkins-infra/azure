# Service Principal ID used by the CI to authenticate terraform against the Azure API
# Defined in the (private) repository jenkins-infra/terraform-states (in ./azure/main.tf)
data "azuread_service_principal" "terraform_production" {
  display_name = "terraform-azure-production"
}

module "jenkins_infra_shared_data" {
  source = "./.shared-tools/terraform/modules/jenkins-infra-shared-data"
}

# Resource groups used to store (and lock) our public IPs
resource "azurerm_resource_group" "prod_public_ips" {
  name     = "prod-public-ips"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_resource_group" "prod_public_ips_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "prod-public-ips-sponsorship"
  location = var.location
  tags     = local.default_tags
}

data "azurerm_client_config" "current" {
}
