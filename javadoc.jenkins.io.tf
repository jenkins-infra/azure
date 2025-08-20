## TODO uncomment to use proper naming convention
# moved {
#   from = azurerm_resource_group.javadoc
#   to = azurerm_resource_group.javadoc_jenkins_io
# }
# resource "azurerm_resource_group" "javadoc_jenkins_io" {
resource "azurerm_resource_group" "javadoc" {
  name     = "javadoc-jenkins-io"
  location = var.location
}
resource "kubernetes_namespace" "javadoc_jenkins_io" {
  provider = kubernetes.publick8s

  metadata {
    name = "javadoc-jenkins-io"
  }
}
resource "kubernetes_persistent_volume" "javadoc_jenkins_io" {
  provider = kubernetes.publick8s
  metadata {
    name = kubernetes_namespace.javadoc_jenkins_io.metadata[0].name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
    mount_options = [
      "nconnect=4", # Mandatory value (4) for Premium Azure File Share NFS 4.1. Increasing require using NetApp NFS instead ($$$)
      "noresvport", # ref. https://linux.die.net/man/5/nfs
      "actimeo=10", # Data is changed quite often
      "cto",        # Ensure data consistency at the cost of slower I/O
    ]
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = kubernetes_namespace.javadoc_jenkins_io.metadata[0].name
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName      = azurerm_storage_share.data_storage_jenkins_io.name
          storageAccount = azurerm_storage_account.data_storage_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.publick8s_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.publick8s_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "javadoc_jenkins_io" {
  provider = kubernetes.publick8s
  metadata {
    name      = kubernetes_persistent_volume.javadoc_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.javadoc_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.javadoc_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.javadoc_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.javadoc_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.javadoc_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}

### TODO Remove below
moved {
  from = azurerm_resource_group.javadoc_jenkins_io
  to   = azurerm_resource_group.javadocjenkinsio
}
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
