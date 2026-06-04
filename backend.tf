terraform {
  backend "azurerm" {
    subscription_id = "dff2ec18-6a8e-405c-8e45-b7df7465acf0"
    tenant_id       = "4c45fef2-1ba7-4120-80a0-9e2d03e9c2b6"
    key             = "terraform.tfstate"
  }
}
