#
# This terraform plan defines the resources necessary to host trusted.ci.jenkins.io
#

resource "azurerm_resource_group" "trustedci" {
    name     = "${var.prefix}trustedci"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "trustedci" {
    name                = "${var.prefix}trustedci"
    resource_group_name = "${azurerm_resource_group.trustedci.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
    depends_on          = ["azurerm_resource_group.trustedci"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_share" "trustedci" {
    name = "trustedci"
    resource_group_name     = "${azurerm_resource_group.trustedci.name}"
    storage_account_name    = "${azurerm_storage_account.trustedci.name}"
    quota                   = 1024
    depends_on              = ["azurerm_resource_group.trustedci","azurerm_storage_account.trustedci"]
}
