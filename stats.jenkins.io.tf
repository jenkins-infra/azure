resource "azurerm_resource_group" "stats_jenkins_io" {
  name     = "stats-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "stats_jenkins_io" {
  name                       = "statsjenkinsio"
  resource_group_name        = azurerm_resource_group.stats_jenkins_io.name
  location                   = azurerm_resource_group.stats_jenkins_io.location
  account_tier               = "Standard"
  account_replication_type   = "ZRS"
  account_kind               = "StorageV2"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  network_rules {
    default_action = "Deny"
    ip_rules = flatten(concat(
      [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
    ))
    virtual_network_subnet_ids = concat(
      [
        # Required for using and populating the resource
        data.azurerm_subnet.publick8s_tier.id,
      ],
      # Required for managing the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
    )
    bypass = ["AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "stats_jenkins_io" {
  name               = "stats-jenkins-io"
  storage_account_id = azurerm_storage_account.stats_jenkins_io.id
  quota              = 5
}
