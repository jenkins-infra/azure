resource "azurerm_resource_group" "weekly_ci_jenkins_io" {
  name     = "weekly-ci-jenkins-io"
  location = var.location
}
resource "azurerm_managed_disk" "weekly_ci_jenkins_io" {
  name                 = "weekly-ci-jenkins-io"
  location             = azurerm_resource_group.weekly_ci_jenkins_io.location
  resource_group_name  = azurerm_resource_group.weekly_ci_jenkins_io.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 8
  tags                 = local.default_tags
}

## Sponsored

resource "azurerm_resource_group" "weekly_ci_jenkins_io_sponsored" {
  provider = kubernetes.publick8s_sponsored

  name     = "weekly-ci-jenkins-io-sponsored"
  location = var.location
}
resource "azurerm_managed_disk" "weekly_ci_jenkins_io_sponsored" {
  provider = kubernetes.publick8s_sponsored

  name                 = "weekly-ci-jenkins-io-sponsored"
  location             = azurerm_resource_group.weekly_ci_jenkins_io_sponsored.location
  resource_group_name  = azurerm_resource_group.weekly_ci_jenkins_io_sponsored.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 8
  tags                 = local.default_tags
}
