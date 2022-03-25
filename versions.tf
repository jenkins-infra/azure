
terraform {
  required_version = ">= 1.1, <1.2"
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    local = {
      source = "hashicorp/local"
    }
    postgresql = {
      source = "cyrilgdn/postgresql"
    }
  }
}
