# Storage account
resource "azurerm_resource_group" "updates_jenkins_io" {
  name     = "updates-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "updates_jenkins_io" {
  name                     = "updatesjenkinsio"
  resource_group_name      = azurerm_resource_group.updates_jenkins_io.name
  location                 = azurerm_resource_group.updates_jenkins_io.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # default value, needed for tfsec

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

resource "azurerm_storage_share" "updates_jenkins_io" {
  name                 = "updates-jenkins-io"
  storage_account_name = azurerm_storage_account.updates_jenkins_io.name
  quota                = 2 # updates.jenkins.io total size in /www/updates.jenkins.io: 400Mo (Mid 2023)
}

data "azurerm_storage_account_sas" "updates_jenkins_io" {
  connection_string = azurerm_storage_account.updates_jenkins_io.primary_connection_string
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

  start  = "2024-01-01T00:00:00Z"
  expiry = "2024-03-01T00:00:00Z"

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

output "updates_jenkins_io_share_url" {
  value = azurerm_storage_share.updates_jenkins_io.url
}

output "updates_jenkins_io_sas_query_string" {
  sensitive = true
  value     = data.azurerm_storage_account_sas.updates_jenkins_io.sas
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

# Azure service CNAME record
resource "azurerm_dns_cname_record" "azure_updates_jenkins_io" {
  name                = "azure.updates"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = azurerm_dns_a_record.public_publick8s.fqdn
  tags                = local.default_tags
}

# DigitalOcean service CNAME record pointing to the doks-public A record defined in https://github.com/jenkins-infra/azure-net/blob/main/dns-records.tf
data "azurerm_dns_a_record" "doks_public_public_ipv4_address" {
  name                = "doks-public-public-ipv4-address"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
}
resource "azurerm_dns_cname_record" "digitalocean_updates_jenkins_io" {
  name                = "digitalocean.updates"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = data.azurerm_dns_a_record.doks_public_public_ipv4_address.fqdn
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
