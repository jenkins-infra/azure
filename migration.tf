#########################################################################################
# Temp. ressources for release.ci.jenkins.io migration from CDF to sponsored subscription
#########################################################################################
resource "azurerm_managed_disk" "release_ci_jenkins_io_data_import_sponsored" {
  provider = azurerm.jenkins-sponsored

  name                 = "release-ci-jenkins-io-data-temp-import"
  location             = azurerm_resource_group.release_ci_jenkins_io_controller_sponsored.location
  resource_group_name  = azurerm_resource_group.release_ci_jenkins_io_controller_sponsored.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Copy"                                                                                                                                                          # requires source_resource_id  to be set!
  source_resource_id   = "/subscriptions/1e7d5219-acbc-4495-8629-bdbb22e9b3ed/resourceGroups/backups/providers/Microsoft.Compute/snapshots/2026-05-27-15h35Z-release-ci-jenkins-io-data" # requires create_option to be set to "Copy"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
resource "kubernetes_persistent_volume" "privatek8s_sponsored_release_ci_jenkins_io_data_import" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name = "release-ci-jenkins-io-data-import"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.release_ci_jenkins_io_data_import_sponsored.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_sponsored_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.release_ci_jenkins_io_data_import_sponsored.id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_sponsored_release_ci_jenkins_io_data_import" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "release-ci-jenkins-io-data-import"
    namespace = kubernetes_namespace.privatek8s_sponsored["release-ci-jenkins-io"].metadata.0.name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data_import.spec.0.access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data_import.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data_import.spec.0.storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data_import.spec.0.capacity.storage
      }
    }
  }
}

#########################################################################################
# Temp. ressources for infra.ci.jenkins.io migration from CDF to sponsored subscription
#########################################################################################
resource "azurerm_managed_disk" "infra_ci_jenkins_io_data_import_sponsored" {
  provider = azurerm.jenkins-sponsored

  name                 = "infra-ci-jenkins-io-data-temp-import"
  location             = azurerm_resource_group.infra_ci_jenkins_io_controller_sponsored.location
  resource_group_name  = azurerm_resource_group.infra_ci_jenkins_io_controller_sponsored.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Copy"                                                                                                                                                        # requires source_resource_id  to be set!
  source_resource_id   = "/subscriptions/1e7d5219-acbc-4495-8629-bdbb22e9b3ed/resourceGroups/backups/providers/Microsoft.Compute/snapshots/2026-05-27-16h52Z-infra-ci-jenkins-io-data" # requires create_option to be set to "Copy"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
resource "kubernetes_persistent_volume" "privatek8s_sponsored_infra_ci_jenkins_io_data_import" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name = "infra-ci-jenkins-io-data-import"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.infra_ci_jenkins_io_data_import_sponsored.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_sponsored_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.infra_ci_jenkins_io_data_import_sponsored.id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_sponsored_infra_ci_jenkins_io_data_import" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "infra-ci-jenkins-io-data-import"
    namespace = kubernetes_namespace.privatek8s_sponsored["infra-ci-jenkins-io"].metadata.0.name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data_import.spec.0.access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data_import.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data_import.spec.0.storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data_import.spec.0.capacity.storage
      }
    }
  }
}
