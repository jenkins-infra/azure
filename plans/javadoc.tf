#
# This terraform plan defines the resources necessary to host javadoc.jenkins.io
#

resource "azurerm_resource_group" "javadoc" {
  name     = "${var.prefix}javadoc"
  location = var.location

  tags = {
    env = var.prefix
  }
}

resource "azurerm_storage_account" "javadoc" {
  name                     = "${var.prefix}javadoc"
  resource_group_name      = azurerm_resource_group.javadoc.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  depends_on               = [azurerm_resource_group.javadoc]

  tags = {
    env = var.prefix
  }
}

resource "azurerm_storage_share" "javadoc" {
  name                 = "javadoc"
  storage_account_name = azurerm_storage_account.javadoc.name
  depends_on = [
    azurerm_resource_group.javadoc,
    azurerm_storage_account.javadoc,
  ]
}

