## This file contains the resources associated to the buckets used to store private and public reports

############# Legacy resources to be removed once migrated to the new resources below
resource "azurerm_resource_group" "prod_reports" {
  name     = "prod-reports"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_account" "prodjenkinsreports" {
  name                       = "prodjenkinsreports"
  resource_group_name        = azurerm_resource_group.prod_reports.name
  location                   = azurerm_resource_group.prod_reports.location
  account_tier               = "Standard"
  account_replication_type   = "GRS"
  account_kind               = "Storage"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = {
    scope = "terraform-managed"
  }
}
############# End of legacy resources to be removed once migrated to the new resources below

resource "azurerm_resource_group" "reports_jenkins_io" {
  name     = "reports-jenkins-io"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_account" "reports_jenkins_io" {
  name                       = "reportsjenkinsio"
  resource_group_name        = azurerm_resource_group.reports_jenkins_io.name
  location                   = azurerm_resource_group.reports_jenkins_io.location
  account_tier               = "Standard"
  account_replication_type   = "ZRS"
  account_kind               = "StorageV2"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  network_rules {
    default_action = "Deny"
    ip_rules = flatten(concat(
      [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
    ))
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
      ],
      # Required for managing and populating the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["release.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["trusted.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["cert.ci.jenkins.io"].agents,
    )
    bypass = ["AzureServices"]
  }

  tags = {
    scope = "terraform-managed"
  }
}

# Resources used for builds.reports.jenkins.io web service
resource "azurerm_storage_share" "builds_reports_jenkins_io" {
  name               = "builds-reports-jenkins-io"
  storage_account_id = azurerm_storage_account.reports_jenkins_io.id
  # Less than 50Mb of files
  quota = 1
}
resource "kubernetes_namespace" "builds_reports_jenkins_io" {
  provider = kubernetes.publick8s

  metadata {
    name = azurerm_storage_share.builds_reports_jenkins_io.name
    labels = {
      name = azurerm_storage_share.builds_reports_jenkins_io.name
    }
  }
}
resource "kubernetes_secret" "builds_reports_jenkins_io" {
  provider = kubernetes.publick8s

  metadata {
    name      = azurerm_storage_share.builds_reports_jenkins_io.name
    namespace = azurerm_storage_share.builds_reports_jenkins_io.name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.reports_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.reports_jenkins_io.primary_access_key
  }

  type = "Opaque"
}
resource "kubernetes_persistent_volume" "builds_reports_jenkins_io" {
  provider = kubernetes.publick8s
  metadata {
    name = azurerm_storage_share.builds_reports_jenkins_io.name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.builds_reports_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {                                                                   # To ensure no other PVCs can claim this PV
      namespace = kubernetes_namespace.builds_reports_jenkins_io.metadata[0].name # Namespace is required even though it's in "default" namespace.
      name      = azurerm_storage_share.builds_reports_jenkins_io.name            # Name of your PVC (cannot be a direct reference to avoid cyclical errors)
    }
    mount_options = [
      "dir_mode=0777",
      "file_mode=0777",
      "uid=0",
      "gid=0",
      "mfsymlinks",
      "cache=strict", # Default on usual kernels but worth setting it explicitly
      "nosharesock",  # Use new TCP connection for each CIFS mount (need more memory but avoid lost packets to create mount timeouts)
      "nobrl",        # disable sending byte range lock requests to the server and for applications which have challenges with posix locks
    ]
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = format("%s-%s", azurerm_storage_account.reports_jenkins_io.name, azurerm_storage_share.builds_reports_jenkins_io.name)
        read_only     = true
        volume_attributes = {
          resourceGroup = azurerm_storage_account.reports_jenkins_io.resource_group_name
          shareName     = azurerm_storage_share.builds_reports_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.builds_reports_jenkins_io.metadata[0].name
          namespace = kubernetes_secret.builds_reports_jenkins_io.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "builds_reports_jenkins_io" {
  provider = kubernetes.publick8s
  metadata {
    name      = kubernetes_persistent_volume.builds_reports_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.builds_reports_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.builds_reports_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.builds_reports_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.builds_reports_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.builds_reports_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}
