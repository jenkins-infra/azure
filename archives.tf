resource "azurerm_resource_group" "archives" {
  name     = "archives"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "archives" {
  name                            = "archives"
  resource_group_name             = azurerm_resource_group.archives.name
  location                        = azurerm_resource_group.archives.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS" # recommended for backups
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  # https://learn.microsoft.com/en-gb/azure/storage/common/infrastructure-encryption-enable
  infrastructure_encryption_enabled = true

  tags = local.default_tags
}

## Archived items

# Container for the dump of confluence databases, see https://github.com/jenkins-infra/helpdesk/issues/3249
resource "azurerm_storage_container" "confluence_dumps" {
  name                  = "confluencedatabasedumps"
  storage_account_name  = azurerm_storage_account.archives.name
  container_access_type = "private"
  metadata = merge(local.default_tags, {
    helpdesk = "https://github.com/jenkins-infra/helpdesk/issues/3249"
  })
}
