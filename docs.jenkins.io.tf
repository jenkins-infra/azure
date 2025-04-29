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
    ip_rules = flatten(concat(
      [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
    ))
    virtual_network_subnet_ids = [
      data.azurerm_subnet.publick8s_tier.id,
      data.azurerm_subnet.privatek8s_sponsorship_tier.id,                      # required for management from infra.ci (terraform)
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
    ]
    bypass = ["AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "docs_jenkins_io" {
  name               = "docs-jenkins-io"
  storage_account_id = azurerm_storage_account.docs_jenkins_io.id
  quota              = 5
}
