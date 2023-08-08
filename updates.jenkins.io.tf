# Storage account
resource "azurerm_resource_group" "updates_jenkins_io" {
  name     = "updates-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "updates_jenkins_io" {
  name                          = "updatesjenkinsio"
  resource_group_name           = azurerm_resource_group.updates_jenkins_io.name
  location                      = azurerm_resource_group.updates_jenkins_io.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  min_tls_version               = "TLS1_2" # default value, needed for tfsec
  public_network_access_enabled = "true"   # Explicit default value, we want this storage account to be readable from anywhere

  tags = local.default_tags
}

resource "azurerm_storage_share" "updates_jenkins_io" {
  name                 = "updates-jenkins-io"
  storage_account_name = azurerm_storage_account.updates_jenkins_io.name
  quota                = 2 # updates.jenkins.io total size in /www/updates.jenkins.io: 400Mo (Mid 2023)
}

output "updates_jenkins_io_storage_account_primary_access_key" {
  sensitive = true
  value     = azurerm_storage_account.updates_jenkins_io.primary_access_key
}

# Redis database
resource "azurerm_redis_cache" "updates_jenkins_io" {
  name                = "updates-jenkins-io"
  location            = azurerm_resource_group.updates_jenkins_io.location
  resource_group_name = azurerm_resource_group.updates_jenkins_io.name
  capacity            = 1
  family              = "C"        # Basic/Standard SKU family
  sku_name            = "Standard" # A replicated cache in a two node Primary/Secondary configuration managed by Microsoft, with a high availability SLA.
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  tags = local.default_tags
}

output "updates_jenkins_io_redis_hostname" {
  value = azurerm_redis_cache.updates_jenkins_io.hostname
}

output "updates_jenkins_io_redis_primary_access_key" {
  sensitive = true
  value     = azurerm_redis_cache.updates_jenkins_io.primary_access_key
}

# Service DNS record
resource "azurerm_dns_cname_record" "azure_updates_jenkins_io" {
  name                = "azure.updates"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = azurerm_dns_a_record.public_publick8s.fqdn
  tags                = local.default_tags
}
