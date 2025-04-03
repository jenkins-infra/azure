resource "azurerm_resource_group" "ci_jenkins_io" {
  provider = azurerm.jenkins-sponsorship
  name     = "ci-jenkins-io"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "ci_jenkins_io" {
  provider            = azurerm.jenkins-sponsorship
  name                = "cijenkinsio"
  resource_group_name = azurerm_resource_group.ci_jenkins_io.name
  location            = azurerm_resource_group.ci_jenkins_io.location

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
      data.azurerm_subnet.ci_jenkins_io_controller_sponsorship.id,
      data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.id,
      data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id,
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci container VM agents
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}
resource "azurerm_storage_share" "ci_jenkins_io_maven_cache" {
  name               = "ci-jenkins-io-maven-cache"
  storage_account_id = azurerm_storage_account.ci_jenkins_io.id
  quota              = 100 # Minimum size of premium is 100 - https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioning-method
}

## Service DNS records
resource "azurerm_dns_cname_record" "ci_jenkins_io" {
  name                = trimsuffix(trimsuffix(local.ci_jenkins_io_fqdn, data.azurerm_dns_zone.jenkinsio.name), ".")
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = "aws.ci.jenkins.io"
  tags                = local.default_tags
}
resource "azurerm_dns_cname_record" "assets_ci_jenkins_io" {
  name                = "assets.${azurerm_dns_cname_record.ci_jenkins_io.name}"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = "assets.aws.ci.jenkins.io"
  tags                = local.default_tags
}
