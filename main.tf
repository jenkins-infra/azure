# This data source allows referencing the identity used by Terraform to connect to the Azure API
data "azuread_client_config" "current" {}
