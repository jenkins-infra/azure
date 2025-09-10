resource "azurerm_resource_group" "get_jenkins_io" {
  name     = "get-jenkins-io"
  location = var.location
  tags     = local.default_tags
}
resource "kubernetes_namespace" "get_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "get-jenkins-io"
  }
}
resource "kubernetes_persistent_volume" "get_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = kubernetes_namespace.get_jenkins_io.metadata[0].name
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
        volume_handle = kubernetes_namespace.get_jenkins_io.metadata[0].name
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
resource "kubernetes_persistent_volume_claim" "get_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = kubernetes_persistent_volume.get_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.get_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.get_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.get_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.get_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.get_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}
