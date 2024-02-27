resource "azurerm_resource_group" "javadoc_jenkins_io" {
  name     = "javadocjenkinsio"
  location = var.location
}

resource "azurerm_storage_account" "javadoc_jenkins_io" {
  name                              = "javadocjenkinsio"
  resource_group_name               = azurerm_resource_group.javadoc_jenkins_io.name
  location                          = azurerm_resource_group.javadoc_jenkins_io.location
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
      data.azurerm_subnet.privatek8s_tier.id, # required for management from infra.ci (terraform)
      data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.id,
      data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.id,
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "javadoc_jenkins_io" {
  name                 = "javadoc-jenkins-io"
  storage_account_name = azurerm_storage_account.javadoc_jenkins_io.name
  quota                = 100 # Minimum size when using a Premium storage account
}
