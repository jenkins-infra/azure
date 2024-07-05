resource "azurerm_resource_group" "ldap" {
  name     = "ldap"
  location = var.location
  tags     = local.default_tags
}

## LDAP uses the following data disk for its `/var/lib/ldap` data directory
resource "azurerm_managed_disk" "ldap_jenkins_io_data" {
  name                = "ldap-jenkins-io-data"
  location            = azurerm_resource_group.ldap.location
  resource_group_name = azurerm_resource_group.ldap.name
  # ZRS to ensure we can move service across AZs
  # Standard because it is enough for LDAP's IOPS and I/O bandwidth
  # Ref. https://azure.microsoft.com/en-us/pricing/details/managed-disks/
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  # LDAP data set is between 300 and 500 Mb
  # Class E1 (4G) only allow 7800 paid transactions per hour, while LDAP may peak at 8500 sometimes so E2 it is
  # Ref. https://azure.microsoft.com/en-us/pricing/details/managed-disks/
  disk_size_gb = 8
  tags         = local.default_tags
}
resource "kubernetes_persistent_volume" "ldap_jenkins_io_data" {
  provider = kubernetes.publick8s
  metadata {
    name = "ldap-jenkins-io-pv"
  }
  spec {
    capacity = {
      storage = azurerm_managed_disk.ldap_jenkins_io_data.disk_size_gb
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisionned_publick8s.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.ldap_jenkins_io_data.id
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "ldap_jenkins_io_data" {
  provider = kubernetes.publick8s
  metadata {
    name      = "ldap-jenkins-io-data"
    namespace = "ldap"
  }
  spec {
    access_modes       = kubernetes_persistent_volume.ldap_jenkins_io_data.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.ldap_jenkins_io_data.metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned_publick8s.id
    resources {
      requests = {
        storage = azurerm_managed_disk.ldap_jenkins_io_data.disk_size_gb
      }
    }
  }
}

# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "ldap_jenkins_io_controller_disk_reader" {
  name  = "ReadLDAPDisk"
  scope = azurerm_resource_group.ldap.id

  permissions {
    actions = ["Microsoft.Compute/disks/read"]
  }
}
resource "azurerm_role_assignment" "ldap_jenkins_io_allow_azurerm" {
  scope              = azurerm_resource_group.ldap.id
  role_definition_id = azurerm_role_definition.ldap_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
}

## LDAP is backed-up (at regular intervals and on stopping) by a side container into the following Azure file storage
resource "azurerm_storage_account" "ldap_backups" {
  name                     = "ldapjenkinsiobackups"
  resource_group_name      = azurerm_resource_group.ldap.name
  location                 = azurerm_resource_group.ldap.location
  account_tier             = "Standard"
  account_replication_type = "GRS" # recommended for backups
  # https://learn.microsoft.com/en-gb/azure/storage/common/infrastructure-encryption-enable
  infrastructure_encryption_enabled = true
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec

  tags = local.default_tags
}
resource "azurerm_storage_account_network_rules" "ldap_access" {
  storage_account_id = azurerm_storage_account.ldap_backups.id

  default_action = "Deny"
  ip_rules = flatten(concat(
    [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
  ))
  virtual_network_subnet_ids = [
    data.azurerm_subnet.publick8s_tier.id,
    data.azurerm_subnet.privatek8s_tier.id,                                  # required for management from infra.ci (terraform)
    data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
    data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
  ]
  # Grant access to trusted Azure Services like Azure Backup (see # https://learn.microsoft.com/en-gb/azure/storage/common/storage-network-security?tabs=azure-portal#exceptions)
  bypass = ["AzureServices"]
}
# TODO: find out how to create this without the 403 error encountered in #394, #396 & #398
# resource "azurerm_storage_share" "ldap" {
#   name                 = "ldap"
#   storage_account_name = azurerm_storage_account.ldap_backups.name
#   quota                = 5120 # 5To
# }
output "ldap_backups_primary_access_key" {
  value     = azurerm_storage_account.ldap_backups.primary_access_key
  sensitive = true
}
