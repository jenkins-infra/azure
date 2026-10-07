# Service Principal ID used by the CI to authenticate terraform against the Azure API
# Defined in the (private) repository jenkins-infra/terraform-states (in ./azure/main.tf)
data "azuread_service_principal" "terraform_production" {
  display_name = "terraform-azure-production"
}

# Resource groups used to store (and lock) our public IPs
resource "azurerm_resource_group" "prod_public_ips" {
  name     = "prod-public-ips"
  location = var.location
  tags     = local.default_tags
}
# Resource groups used to store (and lock) our public IPs for publick8s
resource "azurerm_resource_group" "prod_publick8s_ips_sponsored" {
  provider = azurerm.jenkins-sponsored
  name     = "prod-public-ips" # Same name to avoid Public IP to complain when moved
  location = var.location
  tags     = local.default_tags
}
# Resource groups used to store (and lock) our public IPs for privatek8s
resource "azurerm_resource_group" "prod_public_ips_sponsored" {
  provider = azurerm.jenkins-sponsored
  name     = "prod-public-ips-sponsored"
  location = var.location
  tags     = local.default_tags
}

data "azurerm_client_config" "current" {
}
