#
# This terraform plan defines the resources necessary to host plugins.jenkins.io
#

resource "azurerm_resource_group" "pluginsite" {
  name     = "${var.prefix}pluginsite"
  location = var.location

  tags = {
    env = var.prefix
  }
}

resource "azurerm_storage_account" "pluginsite" {
  name                     = "${var.prefix}pluginsite"
  resource_group_name      = azurerm_resource_group.pluginsite.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  depends_on               = [azurerm_resource_group.pluginsite]

  tags = {
    env = var.prefix
  }
}

resource "azurerm_storage_share" "pluginsite" {
  name                 = "pluginsite"
  resource_group_name  = azurerm_resource_group.pluginsite.name
  storage_account_name = azurerm_storage_account.pluginsite.name
  depends_on = [
    azurerm_resource_group.pluginsite,
    azurerm_storage_account.pluginsite,
  ]
}

