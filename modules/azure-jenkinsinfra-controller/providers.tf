terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      configuration_aliases = [azurerm.dns]
    }
    azuread = {
      source = "hashicorp/azuread"
    }
  }
}
