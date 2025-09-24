# resource "azurerm_resource_group" "javadoc_jenkins_io" {
resource "azurerm_resource_group" "javadoc" {
  name     = "javadoc-jenkins-io"
  location = var.location
}

### TODO Remove below
resource "azurerm_resource_group" "javadocjenkinsio" {
  name     = "javadocjenkinsio"
  location = var.location
}
resource "azurerm_storage_account" "javadoc_jenkins_io" {
  name                              = "javadocjenkinsio"
  resource_group_name               = azurerm_resource_group.javadocjenkinsio.name
  location                          = azurerm_resource_group.javadocjenkinsio.location
  account_tier                      = "Premium"
  account_kind                      = "FileStorage"
  access_tier                       = "Hot"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
        data.azurerm_subnet.publick8s.id,
      ],
      # Required for managing the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
      # Required for populating the resource when a release is performed
      local.app_subnets["trusted.ci.jenkins.io"].agents,
    )
    bypass = ["Metrics", "Logging", "AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "javadoc_jenkins_io" {
  name               = "javadoc-jenkins-io"
  storage_account_id = azurerm_storage_account.javadoc_jenkins_io.id
  quota              = 100 # Minimum size when using a Premium storage account
}
