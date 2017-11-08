#
# This terraform plan defines the resources necessary to store varied backups
# for Jenkins hosts to publish to
#
# See: https://issues.jenkins-ci.org/browse/INFRA-1148

resource "azurerm_resource_group" "backups" {
    name     = "${var.prefix}-backups"
    location = "${var.location}"
}

resource "azurerm_storage_account" "backups" {
    name                     = "${var.prefix}jenkinsbackups"
    resource_group_name      = "${azurerm_resource_group.backups.name}"
    location                 = "${var.location}"
    account_tier              = "Standard"
    account_replication_type = "GRS"
}

# Private backups are those which are going to contain sensitive information or
# user data. Most things will fit into this storage container
resource "azurerm_storage_container" "private_backups" {
    name                  = "privatebackups"
    resource_group_name   = "${azurerm_resource_group.backups.name}"
    storage_account_name  = "${azurerm_storage_account.backups.name}"
    container_access_type = "private"
}

# Public backups are for those things which are generated data, or otherwise
# already existing public data, such as meeting minutes, etc.
resource "azurerm_storage_container" "public_backups" {
    name                  = "publicbackups"
    resource_group_name   = "${azurerm_resource_group.backups.name}"
    storage_account_name  = "${azurerm_storage_account.backups.name}"
    container_access_type = "container"
}
