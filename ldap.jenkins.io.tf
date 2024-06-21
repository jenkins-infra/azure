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

  default_action = "Deny"
  ip_rules = flatten(concat(
    [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
  ))
  virtual_network_subnet_ids = [
    data.azurerm_subnet.publick8s_tier.id,
    data.azurerm_subnet.privatek8s_tier.id,                                  # required for management from infra.ci (terraform)
    data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
    data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
  ]
  # Grant access to trusted Azure Services like Azure Backup (see # https://learn.microsoft.com/en-gb/azure/storage/common/storage-network-security?tabs=azure-portal#exceptions)
  bypass = ["AzureServices"]
}

# TODO: find out how to create this without the 403 error encountered in #394, #396 & #398
# resource "azurerm_storage_share" "ldap" {
#   name                 = "ldap"
#   storage_account_name = azurerm_storage_account.ldap_backups.name
#   quota                = 5120 # 5To
# }

output "ldap_backups_primary_access_key" {
  value     = azurerm_storage_account.ldap_backups.primary_access_key
  sensitive = true
}
