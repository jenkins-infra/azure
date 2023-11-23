resource "azurerm_resource_group" "contributors_jenkins_io" {
  name     = "contributors-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

moved {
  from = azurerm_storage_account.contributorsjenkinsio
  to   = azurerm_storage_account.contributors_jenkins_io
}
resource "azurerm_storage_account" "contributors_jenkins_io" {
  name                      = "contributorsjenkinsio"
  resource_group_name       = azurerm_resource_group.contributors_jenkins_io.name
  location                  = azurerm_resource_group.contributors_jenkins_io.location
  account_tier              = "Standard"
  account_replication_type  = "GRS"
  account_kind              = "Storage"
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"

  tags = local.default_tags
}

resource "azurerm_storage_share" "contributors_jenkins_io" {
  name                 = "contributors-jenkins-io"
  storage_account_name = azurerm_storage_account.contributors_jenkins_io.name
  quota                = 5
}
