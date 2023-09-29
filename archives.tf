resource "azurerm_resource_group" "archives" {
  name     = "archives"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "archives" {
  name                     = "jenkinsinfraarchives"
  resource_group_name      = azurerm_resource_group.archives.name
  location                 = azurerm_resource_group.archives.location
  account_tier             = "Standard"
  account_replication_type = "GRS" # recommended for backups
  # https://learn.microsoft.com/en-gb/azure/storage/common/infrastructure-encryption-enable
  infrastructure_encryption_enabled = true
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec

  network_rules {
    default_action = "Deny"
    ip_rules = flatten(concat(
      [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
    ))
    virtual_network_subnet_ids = [data.azurerm_subnet.privatek8s_tier.id]
    bypass                     = ["AzureServices"]
  }

  tags = local.default_tags
}

## Archived items

# Container for the dump of confluence databases
resource "azurerm_storage_container" "confluence_dumps" {
  name                  = "confluence-databases-dump"
  storage_account_name  = azurerm_storage_account.archives.name
  container_access_type = "private"
  metadata = merge(local.default_tags, {
    helpdesk = "https://github.com/jenkins-infra/helpdesk/issues/3249"
  })
}
