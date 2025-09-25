resource "azurerm_resource_group" "reports_jenkins_io" {
  name     = "reports-jenkins-io"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_account" "reports_jenkins_io" {
  name                       = "reportsjenkinsio"
  resource_group_name        = azurerm_resource_group.reports_jenkins_io.name
  location                   = azurerm_resource_group.reports_jenkins_io.location
  account_tier               = "Standard"
  account_replication_type   = "ZRS"
  account_kind               = "StorageV2"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  network_rules {
    default_action = "Deny"
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
        data.azurerm_subnet.publick8s.id,
      ],
      # Required for managing the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
    )
    bypass = ["AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "reports_jenkins_io" {
  name               = "reports-jenkins-io"
  storage_account_id = azurerm_storage_account.reports_jenkins_io.id
  quota              = 5
}

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
import {
  to = azurerm_storage_share.reports
  id = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/prod-reports/providers/Microsoft.Storage/storageAccounts/prodjenkinsreports/fileServices/default/shares/reports"
}
resource "azurerm_storage_share" "reports" {
  name               = "reports"
  storage_account_id = azurerm_storage_account.prodjenkinsreports.id
  quota              = 1
}

############# End of legacy resources to be removed once migrated to the new resources below
