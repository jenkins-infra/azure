############# Legacy resources to be removed once migrated to the new resources below
resource "azurerm_resource_group" "prod_reports" {
  name     = "prod-reports"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_account" "prodjenkinsreports" {
  name                       = "prodjenkinsreports"
  resource_group_name        = azurerm_resource_group.prod_reports.name
  location                   = azurerm_resource_group.prod_reports.location
  account_tier               = "Standard"
  account_replication_type   = "GRS"
  account_kind               = "Storage"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = {
    scope = "terraform-managed"
  }
}
############# End of legacy resources to be removed once migrated to the new resources below
