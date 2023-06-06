resource "azurerm_resource_group" "ldap" {
  name     = "ldap"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "ldap_backups" {
  name                     = "ldapjenkinsiobackups"
  resource_group_name      = azurerm_resource_group.ldap.name
  location                 = azurerm_resource_group.ldap.location
  account_tier             = "Standard"
  account_replication_type = "GRS" # recommended for backups
  # https://learn.microsoft.com/en-gb/azure/storage/common/infrastructure-encryption-enable
  infrastructure_encryption_enabled = true
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec

  tags = local.default_tags
}

resource "azurerm_storage_account_network_rules" "ldap_access" {
  storage_account_id = azurerm_storage_account.ldap_backups.id

  default_action             = "Deny"
  ip_rules                   = values(local.admin_allowed_ips)
  virtual_network_subnet_ids = [data.azurerm_subnet.publick8s_tier.id]
  # Grant access to trusted Azure Services like Azure Backup (see # https://learn.microsoft.com/en-gb/azure/storage/common/storage-network-security?tabs=azure-portal#exceptions)
  bypass = ["AzureServices"]
}
