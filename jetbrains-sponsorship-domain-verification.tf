resource "azurerm_dns_txt_record" "jetbrains_sponsorship_domain_verification" {
  name                = "lib"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60

  record {
    value = "jetbrains-domain-verification=9memu05gp112di1q7gijggppf"
  }

  tags                = local.default_tags
}
