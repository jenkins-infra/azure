#
# This terraform plan defines the resources necessary to host the Jenkins
# project's reports host.
#
# See: https://issues.jenkins-ci.org/browse/INFRA-947

resource "azurerm_resource_group" "reports" {
  name     = "${var.prefix}-reports"
  location = var.location
}

resource "azurerm_storage_account" "reports" {
  name                = "${var.prefix}jenkinsreports"
  resource_group_name = azurerm_resource_group.reports.name

  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  custom_domain {
    name = var.prefix == "prod" ? "reports.jenkins.io" : ""
  }
}

resource "azurerm_storage_container" "reports" {
  name                  = "reports"
  storage_account_name  = azurerm_storage_account.reports.name
  container_access_type = "container"
}

resource "azurerm_storage_share" "reports" {
  name                 = "reports"
  storage_account_name = azurerm_storage_account.reports.name
  depends_on = [
    azurerm_resource_group.reports,
    azurerm_storage_account.reports,
  ]
}

