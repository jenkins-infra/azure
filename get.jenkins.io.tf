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
      data.azurerm_subnet.privatek8s_tier.id,
      data.azurerm_subnet.privatek8s_release_tier.id,
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}


resource "azurerm_storage_share" "get_jenkins_io" {
  name                 = "mirrorbits"
  storage_account_name = azurerm_storage_account.get_jenkins_io.name
  quota                = 700 # 512.14GiB used (Begining 2024)
}

resource "azurerm_storage_share" "get_jenkins_io_website" {
  name                 = "website"
  storage_account_name = azurerm_storage_account.get_jenkins_io.name
  quota                = 100 # Minimal size, 1.6GiB used in 2020
}
