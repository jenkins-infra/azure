resource "azurerm_resource_group" "jenkins_io" {
  name     = "jenkinsio"
  location = var.location
}

resource "azurerm_storage_account" "jenkins_io" {
  name                              = "jenkinsio"
  resource_group_name               = azurerm_resource_group.jenkins_io.name
  location                          = azurerm_resource_group.jenkins_io.location
  account_tier                      = "Premium"
  account_kind                      = "FileStorage"
  access_tier                       = "Hot"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    ip_rules = flatten(
      concat(
        [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
      )
    )
    virtual_network_subnet_ids = [
      data.azurerm_subnet.publick8s_tier.id,
      data.azurerm_subnet.privatek8s_sponsorship_tier.id,                        # required for management from infra.ci (terraform)
      data.azurerm_subnet.privatek8s_tier.id,                                    # required for management from infra.ci (terraform)
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id,   # infra.ci Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,    # infra.ci container VM agents
      data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.id,             # trusted.ci agents
      data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.id, # trusted.ci update center agent (fallback of other agents)
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "jenkins_io" {
  name               = "jenkins-io"
  storage_account_id = azurerm_storage_account.jenkins_io.id
  quota              = 100 # Minimum size when using a Premium storage account
}
