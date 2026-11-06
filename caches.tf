#############################################################################################
# Used for storing artifact caches (Maven, Grapes, etc.) close to the agents (one per region)
#############################################################################################
resource "azurerm_resource_group" "regional_caches" {
  provider = azurerm.jenkins-sponsored
  name     = "regional-caches"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "cache_east_us_2" {
  provider = azurerm.jenkins-sponsored

  name                       = "cacheeastus2"
  resource_group_name        = azurerm_resource_group.regional_caches.name
  location                   = "East US 2"
  account_tier               = "Standard"
  account_replication_type   = "ZRS"
  account_kind               = "StorageV2"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  public_network_access      = "Enabled"

  network_rules {
    default_action = "Deny"
    virtual_network_subnet_ids = concat(
      # Required for populating and using content
      local.app_subnets["infra.ci.jenkins.io"].agents,
      local.app_subnets["release.ci.jenkins.io"].agents,
      local.app_subnets["trusted.ci.jenkins.io"].agents,
    )
    bypass = ["AzureServices"]
  }

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_share" "cache_east_us_2" {
  provider = azurerm.jenkins-sponsored

  name               = "cache-east-us-2"
  storage_account_id = azurerm_storage_account.cache_east_us_2.id
  quota              = 10
}
module "cache_east_us_2_fileshare_serviceprincipal_writer" {
  source                     = "./modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"
  service_fqdn               = "cache-east-us-2-fileshare-serviceprincipal-writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = local.end_dates.regional_caches.cache_east_us_2_fileshare_serviceprincipal_writer.end_date
  file_share_id              = azurerm_storage_share.cache_east_us_2.id
  storage_account_id         = azurerm_storage_account.cache_east_us_2.id
  default_tags               = local.default_tags
}

resource "azurerm_storage_account" "cache_sweden_central" {
  provider = azurerm.jenkins-sponsored

  name                       = "cacheswedencentral"
  resource_group_name        = azurerm_resource_group.regional_caches.name
  location                   = "Sweden Central"
  account_tier               = "Standard"
  account_replication_type   = "ZRS"
  account_kind               = "StorageV2"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  public_network_access      = "Enabled"

  network_rules {
    default_action = "Deny"
    virtual_network_subnet_ids = concat(
      # Required for using content
      local.app_subnets["cert.ci.jenkins.io"].agents,
    )
    # TODO: track infra.ci.jenkins.io outbound IPs with updatecli, https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
    # Required for populating content from infra.ci.jenkins.io
    ip_rules = [
      "20.57.120.46",
      "52.179.141.53",
      "20.186.168.195",
      "20.65.112.39",
      "20.97.161.208",
      "52.251.34.201",
    ]
    bypass = ["AzureServices"]
  }

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_share" "cache_sweden_central" {
  provider = azurerm.jenkins-sponsored

  name               = "cache-sweden-central"
  storage_account_id = azurerm_storage_account.cache_sweden_central.id
  quota              = 10
}
module "cache_sweden_central_fileshare_serviceprincipal_writer" {
  source                     = "./modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"
  service_fqdn               = "cache-sweden-central-fileshare-serviceprincipal-writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = local.end_dates.regional_caches.cache_sweden_central_fileshare_serviceprincipal_writer.end_date
  file_share_id              = azurerm_storage_share.cache_sweden_central.id
  storage_account_id         = azurerm_storage_account.cache_sweden_central.id
  default_tags               = local.default_tags
}
