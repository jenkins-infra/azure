#
# This terraform plan defines the resources necessary to host accounts.jenkins.io files
#
resource "azurerm_resource_group" "accountapp" {
    name     = "${var.prefix}accountapp"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "accountapp" {
    name                = "${var.prefix}accountapp"
    resource_group_name = "${azurerm_resource_group.accountapp.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
    depends_on          = ["azurerm_resource_group.accountapp"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_share" "accountapp" {
    name = "accountapp"
    resource_group_name     = "${azurerm_resource_group.accountapp.name}"
    storage_account_name    = "${azurerm_storage_account.accountapp.name}"
    quota                   = 10
    depends_on              = ["azurerm_resource_group.accountapp","azurerm_storage_account.accountapp"]
}
