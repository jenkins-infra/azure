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
        split(" ", local.external_services["pkg.origin.jenkins.io"]),
      )
    )
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
      ],
      # Required for managing the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
      # Required for populating the resource when a release is performed
      local.app_subnets["release.ci.jenkins.io"].agents,
    )
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
