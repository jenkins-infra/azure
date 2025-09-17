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

resource "azurerm_resource_group" "prodreleasecore" {
  name     = "prodreleasecore"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_key_vault" "prodreleasecore" {
  tenant_id           = data.azurerm_client_config.current.tenant_id
  name                = "prodreleasecore"
  location            = var.location
  resource_group_name = azurerm_resource_group.prodreleasecore.name
  sku_name            = "standard"

  enabled_for_disk_encryption     = false
  soft_delete_retention_days      = 90
  purge_protection_enabled        = false
  rbac_authorization_enabled      = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  public_network_access_enabled = true
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = local.app_subnets["release.ci.jenkins.io"].agents
  }

  # releasecore Entra Application
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "b6d73004-673f-4099-aa80-30e6e9dae314"

    certificate_permissions = [
      "Get",
      "List",
      "GetIssuers",
      "ListIssuers",
    ]

    key_permissions = [
      "Get",
      "List",
      "Decrypt",
      "Verify",
      "Encrypt",
    ]
    secret_permissions = [
      "Get",
      "List",
    ]
  }
}

######## Persistent Volumes used by the "packaging" job
# kubernetes_namespace.privatek8s["release-ci-jenkins-io-agents"].metadata[0].name
resource "kubernetes_persistent_volume" "privatek8s_release_ci_jenkins_io_agents_data_storage" {
  provider = kubernetes.privatek8s
  metadata {
    name = "release-ci-jenkins-io-agents-data-storage"
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_statically_provisioned.id
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
        volume_handle = "release-ci-jenkins-io-agents-data-storage"
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName      = azurerm_storage_share.data_storage_jenkins_io.name
          storageAccount = azurerm_storage_account.data_storage_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.privatek8s_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.privatek8s_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_release_ci_jenkins_io_agents_data_storage" {
  provider = kubernetes.privatek8s
  metadata {
    name      = "data-storage-jenkins-io"
    namespace = kubernetes_namespace.privatek8s["release-ci-jenkins-io-agents"].metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.spec[0].capacity.storage
      }
    }
  }
}
