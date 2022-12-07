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
  # TODO: set to false and add a network rule allowing only the VPN as soon as this one has been deployed so we can access containers in the mean time.
  public_network_access_enabled = true
  # https://learn.microsoft.com/en-gb/azure/storage/common/infrastructure-encryption-enable
  infrastructure_encryption_enabled = true
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec

  tags = local.default_tags
}

# Archived items

# Container for the dump of confluence databases
resource "azurerm_storage_container" "confluence_dumps" {
  name                  = "confluence-databases-dump"
  storage_account_name  = azurerm_storage_account.archives.name
  container_access_type = "private"
  metadata = merge(local.default_tags, {
    helpdesk = "https://github.com/jenkins-infra/helpdesk/issues/3249"
  })
}
