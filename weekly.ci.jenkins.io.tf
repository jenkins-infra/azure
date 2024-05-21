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
  provider               = kubernetes.publick8s
  metadata {
    name = "jenkins-weekly-pv"
  }
  spec {
    capacity = {
      storage = local.weekly_ci_disk_size
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      azure_disk {
        caching_mode  = "Read Write"
        data_disk_uri = azurerm_managed_disk.jenkins_weekly_data.id
        disk_name     = azurerm_managed_disk.jenkins_weekly_data.name
        kind          = "Managed"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "jenkins_weekly_data" {
  provider               = kubernetes.publick8s
  metadata {
    name = "jenkins-weekly-data"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    volume_name        = kubernetes_persistent_volume.jenkins_weekly_data.metadata.0.name
    resources {
      requests = {
        storage = local.weekly_ci_disk_size
      }
    }
  }
}
