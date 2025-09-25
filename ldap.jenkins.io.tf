resource "azurerm_resource_group" "ldap_jenkins_io" {
  name     = "ldap-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_managed_disk" "ldap_jenkins_io_data" {
  name                = "ldap-jenkins-io-data"
  location            = azurerm_resource_group.ldap_jenkins_io.location
  resource_group_name = azurerm_resource_group.ldap_jenkins_io.name
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
resource "azurerm_storage_account" "ldap_jenkins_io" {
  name                              = "ldapjenkinsio"
  resource_group_name               = azurerm_resource_group.ldap_jenkins_io.name
  location                          = azurerm_resource_group.ldap_jenkins_io.location
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  account_kind                      = "StorageV2"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true     # LDAP data is sensitive, even if password are encrypted

  network_rules {
    default_action = "Deny"
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s.id,
      ],
      # Required for managing the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
    )
    bypass = ["AzureServices"]
  }

  tags = local.default_tags
}
resource "azurerm_storage_share" "ldap_jenkins_io_backups" {
  name               = "ldap"
  storage_account_id = azurerm_storage_account.ldap_jenkins_io.id
  # Unless this is a Premium Storage, we only pay for the storage we consume
  quota = 10
}

## TODO: remove resources below after migration
resource "azurerm_managed_disk" "ldap_jenkins_io_data_orig" {
  name                 = "ldap-jenkins-io-data-orig"
  location             = azurerm_resource_group.ldap_jenkins_io.location
  create_option        = "Copy"
  source_resource_id   = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/ldap/providers/Microsoft.Compute/snapshots/ldap-data-2025-0925"
  resource_group_name  = azurerm_resource_group.ldap_jenkins_io.name
  storage_account_type = "StandardSSD_ZRS"
  disk_size_gb         = 8
  tags                 = local.default_tags
}
