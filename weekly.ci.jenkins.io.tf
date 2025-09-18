resource "azurerm_resource_group" "weekly_ci_controller" {
  name     = "weekly-ci"
  location = var.location
}

resource "azurerm_managed_disk" "jenkins_weekly_data" {
  name                 = "jenkins-weekly-data"
  location             = azurerm_resource_group.weekly_ci_controller.location
  resource_group_name  = azurerm_resource_group.weekly_ci_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 8
  tags                 = local.default_tags
}
