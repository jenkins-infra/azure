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
  virtual_network_subnet_ids = concat(
    [
      # Mounting share in the publick8s AKS cluster
      data.azurerm_subnet.publick8s_tier.id,
    ],
    # Required for managing the resource
    local.app_subnets["infra.ci.jenkins.io"].agents,
  )
  bypass = ["Metrics", "Logging", "AzureServices"]
}
resource "azurerm_storage_share" "ldap" {
  name               = "ldap"
  storage_account_id = azurerm_storage_account.ldap_backups.id
  # Unless this is a Premium Storage, we only pay for the storage we consume. Let's use existing quota.
  quota = 5120 # 5To
}

## Kubernetes Resources (static provision of persistent volumes)
