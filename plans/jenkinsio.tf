#
# This terraform plan defines the resources necessary to host jenkins.io
#

resource "azurerm_resource_group" "jenkinsio" {
    name     = "${var.prefix}jenkinsio"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "jenkinsio" {
    name                     = "${var.prefix}jenkinsio"
    resource_group_name      = "${azurerm_resource_group.jenkinsio.name}"
    location                 = "${var.location}"
    account_tier             = "Standard"
    account_replication_type = "GRS"
    depends_on               = ["azurerm_resource_group.jenkinsio"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_share" "jenkinsio" {
    name = "jenkinsio"
    resource_group_name     = "${azurerm_resource_group.jenkinsio.name}"
    storage_account_name    = "${azurerm_storage_account.jenkinsio.name}"
    quota                   = 10
    depends_on              = ["azurerm_resource_group.jenkinsio","azurerm_storage_account.jenkinsio"]
}
