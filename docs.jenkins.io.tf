resource "azurerm_resource_group" "docs_jenkins_io" {
  name     = "docs-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "docs_jenkins_io" {
  name                       = "docsjenkinsio"
  resource_group_name        = azurerm_resource_group.docs_jenkins_io.name
  location                   = azurerm_resource_group.docs_jenkins_io.location
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

resource "azurerm_storage_share" "docs_jenkins_io" {
  name               = "docs-jenkins-io"
  storage_account_id = azurerm_storage_account.docs_jenkins_io.id
  quota              = 5
}
