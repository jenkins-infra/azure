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
resource "azurerm_private_dns_a_record" "artifact_caching_proxy" {
  provider            = azurerm.jenkins-sponsorship
  name                = "artifact-caching-proxy"
  zone_name           = azurerm_private_dns_zone.dockerhub_mirror["cijenkinsio"].name
  resource_group_name = azurerm_private_dns_zone.dockerhub_mirror["cijenkinsio"].resource_group_name
  ttl                 = 60
  records = [
    # Let's specify an IP at the end of the range to have low probability of being used
    cidrhost(
      data.azurerm_subnet.ci_jenkins_io_ephemeral_agents_jenkins_sponsorship.address_prefixes[0],
      -2,
    )
  ]
}
