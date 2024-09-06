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
