resource "azurerm_resource_group" "jenkins_io" {
  name     = "jenkinsio"
  location = var.location
}

resource "azurerm_storage_account" "jenkins_io" {
  name                     = "jenkinsio"
  resource_group_name      = azurerm_resource_group.jenkins_io.name
  location                 = azurerm_resource_group.jenkins_io.location
  account_tier             = "Premium"
  account_replication_type = "ZRS"

  tags = local.default_tags
}

resource "azurerm_storage_share" "jenkins_io" {
  name                 = "jenkins-io"
  storage_account_name = azurerm_storage_account.contributors_jenkins_io.name
  quota                = 5 # Used capacity end of February 2024: 380Mio
}
