resource "azurerm_resource_group" "release_ci_jenkins_io_controller" {
  name     = "release-ci-jenkins-io-controller"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_user_assigned_identity" "release_ci_jenkins_io_controller" {
  location            = azurerm_resource_group.release_ci_jenkins_io_controller.location
  name                = "releasecijenkinsiocontroller"
  resource_group_name = azurerm_resource_group.release_ci_jenkins_io_controller.name
}
resource "azurerm_managed_disk" "release_ci_jenkins_io_data" {
  name                 = "release-ci-jenkins-io-data"
  location             = azurerm_resource_group.release_ci_jenkins_io_controller.location
  resource_group_name  = azurerm_resource_group.release_ci_jenkins_io_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "release_ci_jenkins_io_controller_disk_reader" {
  name  = "ReadReleaseCIDisk"
  scope = azurerm_resource_group.release_ci_jenkins_io_controller.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_controller_disk_reader" {
  scope              = azurerm_resource_group.release_ci_jenkins_io_controller.id
  role_definition_id = azurerm_role_definition.release_ci_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
}
resource "azurerm_user_assigned_identity" "release_ci_jenkins_io_agents" {
  location            = var.location
  name                = "release-ci-jenkins-io-agents"
  resource_group_name = azurerm_kubernetes_cluster.privatek8s.resource_group_name
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_azurevm_agents_write_buildsreports_share" {
  scope = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.release_ci_jenkins_io_agents.principal_id
}

#### TODO: remove resources below when cleaning up for https://github.com/jenkins-infra/helpdesk/issues/4690
resource "azurerm_managed_disk" "release_ci_jenkins_io_data_import" {
  name                 = "release-ci-jenkins-io-data-import"
  location             = azurerm_resource_group.release_ci_jenkins_io_controller.location
  resource_group_name  = azurerm_resource_group.release_ci_jenkins_io_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Copy"
  source_resource_id   = "/subscriptions/1311c09f-aee0-4d6c-99a4-392c2b543204/resourceGroups/backup-sponsorhip/providers/Microsoft.Compute/snapshots/release.ci-data-20250730-09h12Z"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
resource "kubernetes_persistent_volume" "privatek8s_release_ci_jenkins_io_data_import" {
  provider = kubernetes.privatek8s

  metadata {
    name = "release-ci-jenkins-io-data-import"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.release_ci_jenkins_io_data_import.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.release_ci_jenkins_io_data_import.id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_release_ci_jenkins_io_data_import" {
  provider = kubernetes.privatek8s

  metadata {
    name      = "release-ci-jenkins-io-data-import"
    namespace = kubernetes_namespace.privatek8s["release-ci-jenkins-io"].metadata.0.name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_data_import.spec.0.access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_data_import.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_data_import.spec.0.storage_class_name
    resources {
      requests = {
        storage = "${azurerm_managed_disk.release_ci_jenkins_io_data_import.disk_size_gb}Gi"
      }
    }
  }
}
resource "azurerm_resource_group" "release_ci_jenkins_io_controller_jenkins_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "release-ci-jenkins-io-controller"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_managed_disk" "jenkins_release_data_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "jenkins-release-data"
  location             = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.location
  resource_group_name  = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "release_ci_jenkins_io_controller_sponsorship_disk_reader" {
  provider = azurerm.jenkins-sponsorship
  name     = "ReadReleaseCISponsorshipDisk"
  scope    = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_controller_sponsorship_disk_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.id
  role_definition_id = azurerm_role_definition.release_ci_jenkins_io_controller_sponsorship_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
}
resource "azurerm_user_assigned_identity" "release_ci_jenkins_io_agents_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  location            = var.location
  name                = "release-ci-jenkins-io-agents"
  resource_group_name = azurerm_kubernetes_cluster.privatek8s_sponsorship.resource_group_name
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_azurevm_agents_write_buildsreports_share_sponsorship" {
  scope = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.release_ci_jenkins_io_agents_sponsorship.principal_id
}
####
