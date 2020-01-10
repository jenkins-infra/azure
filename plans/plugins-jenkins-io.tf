#
# This terraform plan defines the resources necessary to host plugins_jenkins_io.jenkins.io
#

resource "azurerm_resource_group" "plugins_jenkins_io" {
  name     = "${var.prefix}plugins_jenkins_io"
  location = "${var.location}"

  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "plugins_jenkins_io" {
  name                     = "${var.prefix}plugins_jenkins_io"
  resource_group_name      = "${azurerm_resource_group.plugins_jenkins_io.name}"
  location                 = "${var.location}"
  account_tier             = "Standard"
  account_replication_type = "GRS"
  depends_on               = ["azurerm_resource_group.plugins_jenkins_io"]

  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_share" "plugins_jenkins_io" {
  name                 = "plugins_jenkins_io"
  resource_group_name  = "${azurerm_resource_group.plugins_jenkins_io.name}"
  storage_account_name = "${azurerm_storage_account.plugins_jenkins_io.name}"
  depends_on           = ["azurerm_resource_group.plugins_jenkins_io", "azurerm_storage_account.plugins_jenkins_io"]
}
