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

## TODO: remove resources below after migration
resource "azurerm_managed_disk" "weekly_ci_jenkins_io_orig" {
  name                 = "weekly-ci-jenkins-io-orig"
  location             = azurerm_resource_group.weekly_ci_jenkins_io.location
  create_option        = "Copy"
  source_resource_id   = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/weekly-ci/providers/Microsoft.Compute/snapshots/data-20250925"
  resource_group_name  = azurerm_resource_group.weekly_ci_jenkins_io.name
  storage_account_type = "StandardSSD_ZRS"
  disk_size_gb         = 8
  tags                 = local.default_tags
}
