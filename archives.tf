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

# Dump of confluence databases, see https://github.com/jenkins-infra/helpdesk/issues/3249
# Should containers be created as code or manually?
