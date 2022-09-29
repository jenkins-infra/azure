## This file contains the resources associated to the buckets used to store private and public reports
resource "azurerm_resource_group" "prod_reports" {
  name     = "prod-reports"
  location = "East US 2"

  tags = {
    scope = "terraform-managed"
  }
}

resource "azurerm_storage_account" "prodjenkinsreports" {
  name                      = "prodjenkinsreports"
  resource_group_name       = azurerm_resource_group.prod_reports.name
  location                  = azurerm_resource_group.prod_reports.location
  account_tier              = "Standard"
  account_replication_type  = "GRS"
  account_kind              = "Storage"
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"

  custom_domain {
    name          = "reports.jenkins.io"
    use_subdomain = false
  }

  tags = {
    scope = "terraform-managed"
  }
}
