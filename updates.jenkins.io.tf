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

  tags = local.default_tags

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    ip_rules = flatten(
      concat(
        [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
      )
    )
    virtual_network_subnet_ids = [
      data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.id,
      data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.id,
      data.azurerm_subnet.trusted_ci_jenkins_io_sponsorship_ephemeral_agents.id,
      data.azurerm_subnet.publick8s_tier.id,
      data.azurerm_subnet.privatek8s_tier.id,                                  # required for management from infra.ci (terraform)
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}
resource "azurerm_storage_share" "updates_jenkins_io_content" {
  name                 = "updates-jenkins-io"
  storage_account_name = azurerm_storage_account.updates_jenkins_io.name
  quota                = 100 # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
}
resource "azurerm_storage_share" "updates_jenkins_io_redirects" {
  name                 = "updates-jenkins-io-redirects"
  storage_account_name = azurerm_storage_account.updates_jenkins_io.name
  quota                = 100 # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
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

# Persistent Data for the httpd services
resource "kubernetes_persistent_volume" "updates_jenkins_io_redirects" {
  provider = kubernetes.publick8s
  metadata {
    name = azurerm_storage_share.updates_jenkins_io_redirects.name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.updates_jenkins_io_redirects.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = azurerm_storage_share.updates_jenkins_io_redirects.name
        read_only     = true
        volume_attributes = {
          resourceGroup = azurerm_resource_group.updates_jenkins_io.name
          shareName     = azurerm_storage_share.updates_jenkins_io_redirects.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.updates_jenkins_io_storage.metadata[0].name
          namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "updates_jenkins_io_redirects" {
  provider = kubernetes.publick8s
  metadata {
    name      = azurerm_storage_share.updates_jenkins_io_redirects.name
    namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
  }
  spec {
    access_modes       = kubernetes_persistent_volume.updates_jenkins_io_redirects.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.updates_jenkins_io_redirects.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.updates_jenkins_io_redirects.spec[0].storage_class_name
    resources {
      requests = {
        storage = "${azurerm_storage_share.updates_jenkins_io_redirects.quota}Gi"
      }
    }
  }
}

# Persistent Data for the mirrorbits services ("repository" in mirrorbits naming)
resource "kubernetes_persistent_volume" "updates_jenkins_io_content" {
  provider = kubernetes.publick8s
  metadata {
    name = azurerm_storage_share.updates_jenkins_io_content.name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.updates_jenkins_io_content.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = azurerm_storage_share.updates_jenkins_io_content.name
        read_only     = true
        volume_attributes = {
          resourceGroup = azurerm_resource_group.updates_jenkins_io.name
          shareName     = azurerm_storage_share.updates_jenkins_io_content.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.updates_jenkins_io_storage.metadata[0].name
          namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "updates_jenkins_io_content" {
  provider = kubernetes.publick8s
  metadata {
    name      = azurerm_storage_share.updates_jenkins_io_content.name
    namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
  }
  spec {
    access_modes       = kubernetes_persistent_volume.updates_jenkins_io_content.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.updates_jenkins_io_content.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.updates_jenkins_io_content.spec[0].storage_class_name
    resources {
      requests = {
        storage = "${azurerm_storage_share.updates_jenkins_io_content.quota}Gi"
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
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = "${kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace}-${azurerm_storage_share.geoip_data.name}"
        read_only     = true
        volume_attributes = {
          resourceGroup = azurerm_resource_group.updates_jenkins_io.name
          shareName     = azurerm_storage_share.geoip_data.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.updates_jenkins_io_storage.metadata[0].name
          namespace = kubernetes_secret.updates_jenkins_io_storage.metadata[0].namespace
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
