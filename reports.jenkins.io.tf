resource "azurerm_resource_group" "reports_jenkins_io" {
  name     = "reports-jenkins-io"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
## trusted.ci.jenkins.io and infra.ci.jenkins.io are using the Storage Account Key to read and write
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
