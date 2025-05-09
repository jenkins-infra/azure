# Storage account
resource "azurerm_resource_group" "get_jenkins_io" {
  name     = "get-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "get_jenkins_io" {
  name                = "getjenkinsio"
  resource_group_name = azurerm_resource_group.get_jenkins_io.name
  location            = azurerm_resource_group.get_jenkins_io.location

  account_tier                      = "Premium"
  account_kind                      = "FileStorage"
  access_tier                       = "Hot"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true

  tags = local.default_tags

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    ip_rules = flatten(
      concat(
        [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
        module.jenkins_infra_shared_data.outbound_ips["pkg.jenkins.io"],
      )
    )
    virtual_network_subnet_ids = [
      data.azurerm_subnet.publick8s_tier.id,
      data.azurerm_subnet.privatek8s_sponsorship_tier.id,                      # required for management from infra.ci (terraform)
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
      data.azurerm_subnet.privatek8s_sponsorship_release_tier.id,              # release.ci agents when running the Core packaging job
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}


resource "azurerm_storage_share" "get_jenkins_io" {
  name               = "mirrorbits"
  storage_account_id = azurerm_storage_account.get_jenkins_io.id
  # 512.14GiB used (Beginning 2024)
  quota = 700
}

resource "azurerm_storage_share" "get_jenkins_io_website" {
  name               = "website"
  storage_account_id = azurerm_storage_account.get_jenkins_io.id
  # Minimal size, 1.6GiB used in 2020
  quota = 100
}
