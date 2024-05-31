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
      data.azurerm_subnet.privatek8s_tier.id,
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id,
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}

output "updates_jenkins_io_storage_account_name" {
  value = azurerm_storage_account.updates_jenkins_io.name
}

resource "azurerm_storage_share" "updates_jenkins_io" {
  name                 = "updates-jenkins-io"
  storage_account_name = azurerm_storage_account.updates_jenkins_io.name
  quota                = 100 # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
}

output "updates_jenkins_io_content_fileshare_name" {
  value = azurerm_storage_share.updates_jenkins_io.name
}

resource "azurerm_storage_share" "updates_jenkins_io_httpd" {
  name                 = "updates-jenkins-io-httpd"
  storage_account_name = azurerm_storage_account.updates_jenkins_io.name
  quota                = 100 # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
}

output "updates_jenkins_io_redirections_fileshare_name" {
  value = azurerm_storage_share.updates_jenkins_io_httpd.name
}

# Redis database
resource "azurerm_redis_cache" "updates_jenkins_io" {
  name                = "updates-jenkins-io"
  location            = azurerm_resource_group.updates_jenkins_io.location
  resource_group_name = azurerm_resource_group.updates_jenkins_io.name
  capacity            = 1
  family              = "C"        # Basic/Standard SKU family
  sku_name            = "Standard" # A replicated cache in a two node Primary/Secondary configuration managed by Microsoft, with a high availability SLA.
  enable_non_ssl_port = true
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

# Azure service CNAME records
resource "azurerm_dns_cname_record" "azure_updates_jenkins_io" {
  name                = "azure.updates"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = azurerm_dns_a_record.public_publick8s.fqdn
  tags                = local.default_tags
}

resource "azurerm_dns_cname_record" "mirrors_updates_jenkins_io" {
  name                = "mirrors.updates"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = azurerm_dns_a_record.public_publick8s.fqdn
  tags                = local.default_tags
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
