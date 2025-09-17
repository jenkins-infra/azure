resource "azurerm_resource_group" "updates_jenkins_io" {
  name     = "updates-jenkins-io"
  location = var.location
  tags     = local.default_tags
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
