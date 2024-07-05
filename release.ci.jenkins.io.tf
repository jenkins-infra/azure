resource "azurerm_resource_group" "release_ci_controller" {
  name     = "release-ci"
  location = var.location
}

resource "azurerm_managed_disk" "jenkins_release_data" {
  name                 = "jenkins-release-data"
  location             = azurerm_resource_group.release_ci_controller.location
  resource_group_name  = azurerm_resource_group.release_ci_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.default_tags
}

resource "kubernetes_persistent_volume" "jenkins_release_data" {
  provider = kubernetes.privatek8s
  metadata {
    name = "jenkins-release-pv"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.jenkins_release_data.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisionned_privatek8s.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.jenkins_release_data.id
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "jenkins_release_data" {
  provider = kubernetes.privatek8s
  metadata {
    name      = "jenkins-release-data"
    namespace = "jenkins-release"
  }
  spec {
    access_modes       = kubernetes_persistent_volume.jenkins_release_data.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.jenkins_release_data.metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned_privatek8s.id
    resources {
      requests = {
        storage = "${azurerm_managed_disk.jenkins_release_data.disk_size_gb}Gi"
      }
    }
  }
}

# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "release_ci_jenkins_io_controller_disk_reader" {
  name  = "ReadreleaseCIDisk"
  scope = azurerm_resource_group.release_ci_controller.id

  permissions {
    actions = ["Microsoft.Compute/disks/read"]
  }
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_allow_azurerm" {
  scope              = azurerm_resource_group.release_ci_controller.id
  role_definition_id = azurerm_role_definition.release_ci_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
}
