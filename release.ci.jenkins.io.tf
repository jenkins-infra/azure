resource "azurerm_resource_group" "release_ci_controller" {
  name     = "release-ci"
  location = "East US 2"
}

resource "azurerm_managed_disk" "jenkins_release_data" {
  name                 = "jenkins-release-data"
  location             = azurerm_resource_group.release_ci_controller.location
  resource_group_name  = azurerm_resource_group.release_ci_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = local.release_ci_disk_size
  tags = {
    environment = azurerm_resource_group.release_ci_controller.name
  }
}

resource "kubernetes_persistent_volume" "jenkins_release_data" {
  provider = kubernetes.publick8s
  metadata {
    name = "jenkins-release-pv"
  }
  spec {
    capacity = {
      storage = local.release_ci_disk_size
    }
    access_modes                     = local.release_ci_access_modes
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
  provider = kubernetes.publick8s
  metadata {
    name      = "jenkins-release-data"
    namespace = "jenkins-release"
  }
  spec {
    access_modes       = local.release_ci_access_modes
    volume_name        = kubernetes_persistent_volume.jenkins_release_data.metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned_privatek8s.id
    resources {
      requests = {
        storage = local.release_ci_disk_size
      }
    }
  }
}

# Required to allow the release controller to read the disk
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
  principal_id       = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
}
