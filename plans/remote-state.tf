#
# This terraform plan defines the resources necessary to host the Terraform
# remote state in Azure Blob Storage as described here:
# <https://www.terraform.io/docs/state/remote/azure.html>

resource "azurerm_resource_group" "tfstate" {
    name     = "${var.prefix}tfstate"
    location = "${var.location}"
}

resource "azurerm_storage_account" "tfstate" {
    name                = "${var.prefix}tfstate"
    resource_group_name = "${azurerm_resource_group.tfstate.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
}

resource "azurerm_storage_container" "tfstate" {
    name                  = "tfstate"
    resource_group_name   = "${azurerm_resource_group.tfstate.name}"
    storage_account_name  = "${azurerm_storage_account.tfstate.name}"
    container_access_type = "private"
}
