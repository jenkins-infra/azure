resource "azurerm_resource_group" "repo_azure_jenkins_io" {
  name     = "repo-azure-jenkins-io"
  location = var.location
}

resource "azurerm_managed_disk" "repo_azure_jenkins_io_data" {
  # TODO: keep this in sync with https://github.com/jenkins-infra/kubernetes-management/blob/187b0bb92620c23f774697ad56d56c51a3925255/config/artifact-caching-proxy__common.yaml#L24
  # and / or https://github.com/jenkins-infra/kubernetes-management/blob/main/config/artifact-caching-proxy_azure.yaml
  count               = 2
  name                = "repo-azure-jenkins-io-data-${count.index}"
  location            = azurerm_resource_group.repo_azure_jenkins_io.location
  resource_group_name = azurerm_resource_group.repo_azure_jenkins_io.name
  # No need for overpriced Premium SSD
  # But ZRS is required to ensure we can move across AZs
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  # Disk usage for the artifact caching proxy is between 5Gb and 17Gb
  # IOPS averages at 5/s with peaks around 60/s
  # Bandwidth averages at 150 Kb/s with peaks at 8Mb/s
  disk_size_gb = 32
  tags         = local.default_tags
}

resource "kubernetes_persistent_volume" "repo_azure_jenkins_io_data" {
  count    = length(azurerm_managed_disk.repo_azure_jenkins_io_data)
  provider = kubernetes.publick8s
  metadata {
    name = "repo-azure-jenkins-io-pv-${count.index}"
  }
  spec {
    capacity = {
      storage = azurerm_managed_disk.repo_azure_jenkins_io_data[count.index].disk_size_gb
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisionned_publick8s.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.repo_azure_jenkins_io_data[count.index].id
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "repo_azure_jenkins_io_data" {
  count    = length(kubernetes_persistent_volume.repo_azure_jenkins_io_data)
  provider = kubernetes.publick8s
  metadata {
    name      = "repo-azure-jenkins-io-data-${count.index}"
    namespace = "artifact-caching-proxy"
  }
  spec {
    access_modes       = kubernetes_persistent_volume.repo_azure_jenkins_io_data[count.index].spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.repo_azure_jenkins_io_data[count.index].metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned_publick8s.id
    resources {
      requests = {
        storage = azurerm_managed_disk.repo_azure_jenkins_io_data[count.index].disk_size_gb
      }
    }
  }
}

# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "repo_azure_jenkins_io_disk_reader" {
  name  = "ReadRepoAzureACPDisk"
  scope = azurerm_resource_group.repo_azure_jenkins_io.id

  permissions {
    actions = ["Microsoft.Compute/disks/read"]
  }
}
resource "azurerm_role_assignment" "repo_azure_jenkins_io_allow_azurerm" {
  count              = length(azurerm_managed_disk.repo_azure_jenkins_io_data)
  scope              = azurerm_resource_group.repo_azure_jenkins_io.id
  role_definition_id = azurerm_role_definition.repo_azure_jenkins_io_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
}
