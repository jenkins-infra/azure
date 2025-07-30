# Storage account
resource "azurerm_resource_group" "updates_jenkins_io" {
  name     = "updates-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "updates_jenkins_io" {
  name                = "updatesjenkinsio"
  resource_group_name = azurerm_resource_group.updates_jenkins_io.name
  location            = azurerm_resource_group.updates_jenkins_io.location

  account_tier                      = "Premium"
  account_kind                      = "FileStorage"
  access_tier                       = "Hot"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true
  # Disabled for NFS - https://learn.microsoft.com/en-us/azure/storage/common/storage-require-secure-transfer?toc=%2Fazure%2Fstorage%2Ffiles%2Ftoc.json
  https_traffic_only_enabled = false

  tags = local.default_tags

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    ip_rules = flatten(
      concat(
        [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
      )
    )
    # Only NFS share means only private network access - https://learn.microsoft.com/en-us/azure/storage/files/files-nfs-protocol#security-and-networking
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
      ],
      # Required for managing the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["trusted.ci.jenkins.io"].agents,
    )
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}
# This storage account is expected to replace both "updates_jenkins_io_content" and "updates_jenkins_io_redirects"
resource "azurerm_storage_share" "updates_jenkins_io_data" {
  name               = "updates-jenkins-io-data"
  storage_account_id = azurerm_storage_account.updates_jenkins_io.id
  quota              = 100   # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
  enabled_protocol   = "NFS" # Require a Premium Storage Account
}

## Kubernetes Resources (static provision of persistent volumes)
resource "kubernetes_namespace" "updates_jenkins_io" {
  provider = kubernetes.publick8s

  metadata {
    name = "updates-jenkins-io"
  }
}
resource "kubernetes_secret" "updates_jenkins_io_storage" {
  provider = kubernetes.publick8s

  metadata {
    name      = "updates-jenkins-io-storage"
    namespace = kubernetes_namespace.updates_jenkins_io.metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.updates_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.updates_jenkins_io.primary_access_key
  }

  type = "Opaque"
}

# Persistent Data available in read and write
resource "kubernetes_persistent_volume" "updates_jenkins_io_data" {
  provider = kubernetes.publick8s
  metadata {
    name = azurerm_storage_share.updates_jenkins_io_data.name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.updates_jenkins_io_data.quota}Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
    mount_options = [
      "nconnect=4", # Mandatory value (4) for Premium Azure File Share NFS 4.1. Increasesing require using NetApp NFS instead ($$$)
      "noresvport", # ref. https://linux.die.net/man/5/nfs
      "actimeo=10", # Data is changed quite often
      "cto",        # Ensure data consistency at the cost of slower I/O
    ]
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = azurerm_storage_share.updates_jenkins_io_data.name
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_resource_group.updates_jenkins_io.name
          shareName      = azurerm_storage_share.updates_jenkins_io_data.name
          storageAccount = azurerm_storage_account.updates_jenkins_io.name
        }
        # Check if still needed with NFS
        node_stage_secret_ref {
          name      = kubernetes_secret.updates_jenkins_io_storage.metadata[0].name
          namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "updates_jenkins_io_data" {
  provider = kubernetes.publick8s
  metadata {
    name      = azurerm_storage_share.updates_jenkins_io_data.name
    namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
  }
  spec {
    access_modes       = kubernetes_persistent_volume.updates_jenkins_io_data.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.updates_jenkins_io_data.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.updates_jenkins_io_data.spec[0].storage_class_name
    resources {
      requests = {
        storage = "${azurerm_storage_share.updates_jenkins_io_data.quota}Gi"
      }
    }
  }
}

# Persistent Data for the mirrorbits services ("geoipdata" in mirrorbits naming)
resource "kubernetes_persistent_volume" "updates_jenkins_io_geoipdata" {
  provider = kubernetes.publick8s
  metadata {
    name = "${kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace}-${azurerm_storage_share.geoip_data.name}"
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.geoip_data.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
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
        volume_handle = "${kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace}-${azurerm_storage_share.geoip_data.name}"
        read_only     = true
        volume_attributes = {
          resourceGroup = azurerm_resource_group.publick8s.name
          shareName     = azurerm_storage_share.geoip_data.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.geoip_data.metadata[0].name
          namespace = kubernetes_secret.geoip_data.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "updates_jenkins_io_geoipdata" {
  provider = kubernetes.publick8s
  metadata {
    name      = "${kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace}-${azurerm_storage_share.geoip_data.name}"
    namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
  }
  spec {
    access_modes       = kubernetes_persistent_volume.updates_jenkins_io_geoipdata.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.updates_jenkins_io_geoipdata.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.updates_jenkins_io_geoipdata.spec[0].storage_class_name
    resources {
      requests = {
        storage = "${azurerm_storage_share.geoip_data.quota}Gi"
      }
    }
  }
}

## NS records for each CloudFlare zone defined in https://github.com/jenkins-infra/cloudflare/blob/main/updates.jenkins.io.tf
# West Europe
resource "azurerm_dns_ns_record" "updates_jenkins_io_cloudflare_zone_westeurope" {
  name                = "westeurope.cloudflare"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  # Should correspond to the "zones_name_servers" output defined in https://github.com/jenkins-infra/cloudflare/blob/main/updates.jenkins.io.tf
  records = ["jaxson.ns.cloudflare.com", "mira.ns.cloudflare.com"]
  tags    = local.default_tags
}
# East US
resource "azurerm_dns_ns_record" "updates_jenkins_io_cloudflare_zone_eastamerica" {
  name                = "eastamerica.cloudflare"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  # Should correspond to the "zones_name_servers" output defined in https://github.com/jenkins-infra/cloudflare/blob/main/updates.jenkins.io.tf
  records = ["jaxson.ns.cloudflare.com", "mira.ns.cloudflare.com"]
  tags    = local.default_tags
}
