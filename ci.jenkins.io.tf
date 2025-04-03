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

  # Temporarily
  public_network_access_enabled = true
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
