resource "azurerm_dns_cname_record" "archives_jenkins_io" {
  for_each = {
    "${data.azurerm_dns_zone.jenkinsio.name}"    = "${data.azurerm_dns_zone.jenkinsio.resource_group_name}",
    "${data.azurerm_dns_zone.jenkinsciorg.name}" = "${data.azurerm_dns_zone.jenkinsciorg.resource_group_name}",
  }
  name                = "archives"
  zone_name           = each.key
  resource_group_name = each.value
  ttl                 = 60
  record              = "archives.do.jenkins.io" # Digital Ocean VM
  tags                = local.default_tags
}
