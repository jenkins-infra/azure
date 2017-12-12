#
# This terraform plan defines the resources necessary to host accounts.jenkins.io files
#
resource "azurerm_resource_group" "ldap" {
    name     = "${var.prefix}ldap"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "ldap" {
    name                      = "${var.prefix}ldap"
    resource_group_name       = "${azurerm_resource_group.ldap.name}"
    location                  = "${var.location}"
    account_tier              = "Standard"
    account_replication_type  = "GRS"
    depends_on                = ["azurerm_resource_group.ldap"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_share" "ldap" {
    name = "ldap"
    resource_group_name     = "${azurerm_resource_group.ldap.name}"
    storage_account_name    = "${azurerm_storage_account.ldap.name}"
    quota                   = 10
    depends_on              = ["azurerm_resource_group.ldap","azurerm_storage_account.ldap"]
}
