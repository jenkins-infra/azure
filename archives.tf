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
      [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
    ))
    virtual_network_subnet_ids = [
      data.azurerm_subnet.privatek8s_sponsorship_tier.id,                      # required for management from infra.ci (terraform)
      data.azurerm_subnet.privatek8s_tier.id,                                  # required for management from infra.ci (terraform)
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
    ]
    bypass = ["AzureServices"]
  }

  tags = local.default_tags
}

## Archived items
# Container for the logs archive (2019 -> 2025) of the legacy `updates.jenkins.io` service which used to be in the 'pkg' CloudBees AWS VM
resource "azurerm_storage_container" "legacy_updatesjio_logs" {
  name                  = "legacy-updatesjio-logs"
  storage_account_id    = azurerm_storage_account.archives.id
  container_access_type = "private"
  metadata = merge(local.default_tags, {
    helpdesk = "https://github.com/jenkins-infra/helpdesk/issues/2649"
  })
}

# Container for the dump of confluence databases
resource "azurerm_storage_container" "confluence_dumps" {
  name                  = "confluence-databases-dump"
  storage_account_id    = azurerm_storage_account.archives.id
  container_access_type = "private"
  metadata = merge(local.default_tags, {
    helpdesk = "https://github.com/jenkins-infra/helpdesk/issues/3249"
  })
}
