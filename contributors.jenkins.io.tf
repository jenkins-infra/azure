resource "azurerm_resource_group" "contributors_jenkins_io" {
  name     = "contributors-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "contributors_jenkins_io" {
  name                      = "contributorsjenkinsio"
  resource_group_name       = azurerm_resource_group.contributors_jenkins_io.name
  location                  = azurerm_resource_group.contributors_jenkins_io.location
  account_tier              = "Standard"
  account_replication_type  = "ZRS"
  account_kind              = "StorageV2"
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"

  network_rules {
    default_action = "Deny"
    ip_rules = flatten(concat(
      [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
    ))
    virtual_network_subnet_ids = [data.azurerm_subnet.privatek8s_tier.id, data.azurerm_subnet.publick8s_tier.id]
    bypass                     = ["AzureServices"]
  }

  tags = local.default_tags
}

resource "azurerm_storage_share" "contributors_jenkins_io" {
  name                 = "contributors-jenkins-io"
  storage_account_name = azurerm_storage_account.contributors_jenkins_io.name
  quota                = 5
}

data "azurerm_storage_account_sas" "contributors_jenkins_io" {
  connection_string = azurerm_storage_account.contributors_jenkins_io.primary_connection_string
  signed_version    = "2022-11-02"

  resource_types {
    service   = true # Ex: list Share
    container = true # Ex: list Files and Directories
    object    = true # Ex: create File
  }

  services {
    blob  = false
    queue = false
    table = false
    file  = true
  }

  start  = "2024-01-22T00:00:00Z"
  expiry = "2024-01-28T00:00:00Z"

  # https://learn.microsoft.com/en-us/rest/api/storageservices/create-account-sas#file-service
  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true
    add     = false
    create  = true
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

output "contributors_jenkins_io_share_url" {
  value = azurerm_storage_share.contributors_jenkins_io.url
}

output "contributors_jenkins_io_sas_query_string" {
  sensitive = true
  value     = data.azurerm_storage_account_sas.contributors_jenkins_io.sas
}
