resource "azurerm_resource_group" "plugins_jenkins_io" {
  name     = "pluginsjenkinsio"
  location = var.location
}

resource "azurerm_storage_account" "plugins_jenkins_io" {
  name                              = "pluginsjenkinsio"
  resource_group_name               = azurerm_resource_group.plugins_jenkins_io.name
  location                          = azurerm_resource_group.plugins_jenkins_io.location
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
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
        # TODO: check if still needed? (used to be infra.ci container agents when they were in the privatek8s cluster)
        data.azurerm_subnet.privatek8s_sponsorship_tier.id,
      ],
      # Required for managing and populating the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
    )
    bypass = ["Metrics", "Logging", "AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "plugins_jenkins_io" {
  name               = "plugins-jenkins-io"
  storage_account_id = azurerm_storage_account.plugins_jenkins_io.id
  quota              = 100 # Minimum size when using a Premium storage account
}
