#
# This terraform plan defines the resources necessary to host plugins.jenkins.io
#

resource "azurerm_resource_group" "pluginshtml" {
  name     = "${var.prefix}pluginshtml"
  location = "${var.location}"

  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "pluginshtml" {
  name                     = "${var.prefix}pluginshtml"
  resource_group_name      = "${azurerm_resource_group.pluginshtml.name}"
  location                 = "${var.location}"
  account_tier             = "Standard"
  account_replication_type = "GRS"
  depends_on               = ["azurerm_resource_group.pluginshtml"]

  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_share" "pluginshtml" {
  name                 = "pluginshtml"
  resource_group_name  = "${azurerm_resource_group.pluginshtml.name}"
  storage_account_name = "${azurerm_storage_account.pluginshtml.name}"
  depends_on           = ["azurerm_resource_group.pluginshtml", "azurerm_storage_account.pluginshtml"]
}
