resource "azurerm_resource_group" "weekly_ci_controller" {
  name     = "weekly-ci"
  location = "East US 2"
}

resource "azurerm_managed_disk" "jenkins_weekly_data" {
  name                 = "jenkins-weekly-data"
  location             = azurerm_resource_group.weekly_ci_controller.location
  resource_group_name  = azurerm_resource_group.weekly_ci_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = local.weekly_ci_disk_size
  tags = {
    environment = azurerm_resource_group.weekly_ci_controller.name
  }
}

resource "kubernetes_persistent_volume" "jenkins_weekly_data" {
  provider = kubernetes.publick8s
  metadata {
    name = "jenkins-weekly-pv"
  }
  spec {
    capacity = {
      storage = local.weekly_ci_disk_size
    }
    access_modes                     = local.weekly_ci_access_modes
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisionned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.jenkins_weekly_data.id
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "jenkins_weekly_data" {
  provider = kubernetes.publick8s
  metadata {
    name      = "jenkins-weekly-data"
    namespace = "jenkins-weekly"
  }
  spec {
    access_modes       = local.weekly_ci_access_modes
    volume_name        = kubernetes_persistent_volume.jenkins_weekly_data.metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned.id
    resources {
      requests = {
        storage = local.weekly_ci_disk_size
      }
    }
  }
}

# Required to allow the weekly controller to read the disk
resource "azurerm_role_definition" "weekly_ci_jenkins_io_controller_disk_reader" {
  name     = "ReadWeeklyCIDisk"
  scope    = azurerm_resource_group.weekly_ci_controller.id

  permissions {
    actions = ["Microsoft.Compute/disks/read"]
  }
}
resource "azurerm_role_assignment" "weekly_ci_jenkins_io_allow_azurerm" {
  scope                 = azurerm_resource_group.weekly_ci_controller.id
  role_definition_name  = "ReadWeeklyCIDisk"
  principal_id          = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
}
