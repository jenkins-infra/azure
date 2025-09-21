resource "azurerm_resource_group" "builds_reports_jenkins_io" {
  name     = "builds-reports-jenkins-io"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_account" "builds_reports_jenkins_io" {
  name                       = "buildsreportsjenkinsio"
  resource_group_name        = azurerm_resource_group.builds_reports_jenkins_io.name
  location                   = azurerm_resource_group.builds_reports_jenkins_io.location
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
      # Required for managing and populating the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["release.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["trusted.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["cert.ci.jenkins.io"].agents,
    )
    bypass = ["AzureServices"]
  }

  tags = {
    scope = "terraform-managed"
  }
}

# Resources used for builds.reports.jenkins.io web service
resource "azurerm_storage_share" "builds_reports_jenkins_io" {
  name               = "builds-reports-jenkins-io"
  storage_account_id = azurerm_storage_account.builds_reports_jenkins_io.id
  # Less than 50Mb of files
  quota = 1
}
