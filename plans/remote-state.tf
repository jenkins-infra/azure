#
# This terraform plan defines the resources necessary to host the Terraform
# remote state in Azure Blob Storage as described here:
# <https://www.terraform.io/docs/state/remote/azure.html>

resource "azurerm_resource_group" "tfstate" {
    name     = "${var.prefix}jenkinsinfra-tfstate"
    location = "East US 2"
}

resource "azurerm_storage_account" "tfstate" {
    name                = "${var.prefix}jenkinstfstate"
    resource_group_name = "${azurerm_resource_group.tfstate.name}"
    location            = "East US 2"
    account_type        = "Standard_GRS"
}

resource "azurerm_storage_container" "tfstate" {
    name                  = "tfstate"
    resource_group_name   = "${azurerm_resource_group.tfstate.name}"
    storage_account_name  = "${azurerm_storage_account.tfstate.name}"
    container_access_type = "private"
}


# Configure the Azure store as our remote state backend
data "terraform_remote_state" "azure_tfstate" {
  backend = "azure"
  config {
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    access_key           = "${azurerm_storage_account.tfstate.primary_access_key}"
    key                  = "terraform.tfstate"
  }
}
