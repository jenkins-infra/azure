# Storage account
resource "azurerm_resource_group" "get_jenkins_io" {
  name     = "get-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "get_jenkins_io" {
  name                = "getjenkinsio"
  resource_group_name = azurerm_resource_group.get_jenkins_io.name
  location            = azurerm_resource_group.get_jenkins_io.location

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
        module.jenkins_infra_shared_data.outbound_ips["pkg.jenkins.io"],
      )
    )
    virtual_network_subnet_ids = [
      data.azurerm_subnet.publick8s_tier.id,
      data.azurerm_subnet.privatek8s_tier.id,
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}


resource "azurerm_storage_share" "get_jenkins_io" {
  name                 = "mirrorbits"
  storage_account_name = azurerm_storage_account.get_jenkins_io.name
  quota                = 700 # 512.14GiB used (Begining 2024)
}

resource "azurerm_storage_share" "get_jenkins_io_website" {
  name                 = "website"
  storage_account_name = azurerm_storage_account.get_jenkins_io.name
  quota                = 50 # 1.6GiB used in 2020
}

data "azurerm_storage_account_sas" "get_jenkins_io" {
  connection_string = azurerm_storage_account.get_jenkins_io.primary_connection_string
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

  start  = "2024-01-25T00:00:00Z"
  expiry = "2024-04-25T00:00:00Z"

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

output "get_jenkins_io_share_url" {
  value = azurerm_storage_share.get_jenkins_io.url
}

output "get_jenkins_io_sas_query_string" {
  sensitive = true
  value     = data.azurerm_storage_account_sas.get_jenkins_io.sas
}
