# Service Principal ID used by the CI to authenticate terraform against the Azure API
# Defined in the (private) repository jenkins-infra/terraform-states (in ./azure/main.tf)
data "azuread_service_principal" "terraform_production" {
  display_name = "terraform-production"
}

# Data source used to retrieve the subscription id
data "azurerm_subscription" "jenkins" {
  subscription_id = local.subscription_main
}

module "jenkins_infra_shared_data" {
  source = "./.shared-tools/terraform/modules/jenkins-infra-shared-data"
}

# Resource group used to store (and lock) oiur public IPs
resource "azurerm_resource_group" "prod_public_ips" {
  name     = "prod-public-ips"
  location = var.location
  tags     = local.default_tags
}

output "jenkins_tenant_id" {
  value = data.azurerm_subscription.jenkins.tenant_id
}

output "jenkins_subscription_id" {
  value = data.azurerm_subscription.jenkins.subscription_id
}
