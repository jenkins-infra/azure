#
# This terraform plan defines the resources necessary to host the Terraform
# remote state in Azure Blob Storage as described here:
# <https://www.terraform.io/docs/state/remote/azure.html>

resource "azurerm_resource_group" "tfstate" {
  name     = "${var.prefix}tfstate"
  location = "${var.location}"
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "${var.prefix}tfstate"
  resource_group_name      = "${azurerm_resource_group.tfstate.name}"
  location                 = "${var.location}"
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "GRS"
  enable_blob_encryption   = true
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = "${azurerm_storage_account.tfstate.name}"
  container_access_type = "private"
}

resource "azurerm_storage_account" "tfstate_datadog" {
  name                     = "${var.prefix}tfstatedatadog"
  resource_group_name      = "${azurerm_resource_group.tfstate.name}"
  location                 = "${var.location}"
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "GRS"
  enable_blob_encryption   = true
}

resource "azurerm_storage_container" "tfstate_datadog" {
  name                  = "tfstatedatadog"
  storage_account_name  = "${azurerm_storage_account.tfstate_datadog.name}"
  container_access_type = "private"
}
