# Storage account
resource "azurerm_resource_group" "data_storage_jenkins_io" {
  name     = "data-storage"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "data_storage_jenkins_io" {
  name                = "datastoragejenkinsio"
  resource_group_name = azurerm_resource_group.data_storage_jenkins_io.name
  location            = azurerm_resource_group.data_storage_jenkins_io.location

  account_tier                      = "Premium"
  account_kind                      = "FileStorage"
  access_tier                       = "Hot"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true
  # Disabled for NFS - https://learn.microsoft.com/en-us/azure/storage/common/storage-require-secure-transfer?toc=%2Fazure%2Fstorage%2Ffiles%2Ftoc.json
  https_traffic_only_enabled = false

  tags = local.default_tags

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    # Only NFS share means only private network access - https://learn.microsoft.com/en-us/azure/storage/files/files-nfs-protocol#security-and-networking
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
        # Allows release.ci.jenkins.io agents to access the mount
        data.azurerm_subnet.privatek8s_release_tier.id,
      ],
      # Required for managing the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["trusted.ci.jenkins.io"].agents,
    )
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}
# This storage account is expected to replace both "data_storage_jenkins_io_content" and "data_storage_jenkins_io_redirects"
resource "azurerm_storage_share" "data_storage_jenkins_io" {
  name               = "data-storage-jenkins-io"
  storage_account_id = azurerm_storage_account.data_storage_jenkins_io.id
  quota              = 750   # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
  enabled_protocol   = "NFS" # Require a Premium Storage Account
}

## Kubernetes Resources (static provision of persistent volumes)
resource "kubernetes_namespace" "publick8s_data_storage_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "data-storage-jenkins-io"
  }
}
resource "kubernetes_secret" "publick8s_data_storage_jenkins_io_storage_account" {
  provider = kubernetes.oldpublick8s

  metadata {
    name      = "data-storage-jenkins-io-storage-account"
    namespace = kubernetes_namespace.publick8s_data_storage_jenkins_io.metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.data_storage_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.data_storage_jenkins_io.primary_access_key
  }

  type = "Opaque"
}
