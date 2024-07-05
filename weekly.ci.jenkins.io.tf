resource "azurerm_resource_group" "weekly_ci_controller" {
  name     = "weekly-ci"
  location = var.location
}

resource "azurerm_managed_disk" "jenkins_weekly_data" {
  name                 = "jenkins-weekly-data"
  location             = azurerm_resource_group.weekly_ci_controller.location
  resource_group_name  = azurerm_resource_group.weekly_ci_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 8
  tags                 = local.default_tags
}

resource "kubernetes_persistent_volume" "jenkins_weekly_data" {
  provider = kubernetes.publick8s
  metadata {
    name = "jenkins-weekly-pv"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.jenkins_weekly_data.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisionned_publick8s.id
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
    access_modes       = kubernetes_persistent_volume.jenkins_weekly_data.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.jenkins_weekly_data.metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned_publick8s.id
    resources {
      requests = {
        storage = "${azurerm_managed_disk.jenkins_weekly_data.disk_size_gb}Gi"
      }
    }
  }
}

# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "weekly_ci_jenkins_io_controller_disk_reader" {
  name  = "ReadWeeklyCIDisk"
  scope = azurerm_resource_group.weekly_ci_controller.id

  permissions {
    actions = ["Microsoft.Compute/disks/read"]
  }
}
resource "azurerm_role_assignment" "weekly_ci_jenkins_io_allow_azurerm" {
  scope              = azurerm_resource_group.weekly_ci_controller.id
  role_definition_id = azurerm_role_definition.weekly_ci_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
}
