# We use a dedicated zone to limit risks of unwanted DNS manipulation
resource "azurerm_dns_zone" "custom_zone" {
  name                = var.zone_name
  resource_group_name = var.dns_rg_name

  tags = var.default_tags
}
# create DNS record of type NS for child-zone in the parent zone (to allow propagation of DNS records)
resource "azurerm_dns_ns_record" "custom_zone_parent_records" {
  name                = trimsuffix(azurerm_dns_zone.custom_zone.name, ".${var.parent_zone_name}") # only the flat name not the fqdn
  zone_name           = var.parent_zone_name
  resource_group_name = var.dns_rg_name
  ttl                 = 60

  records = azurerm_dns_zone.custom_zone.name_servers

  tags = var.default_tags
}
## Permissions assigned to the VM System Identity to allow renewal: only allow reading the dnszone and only allow managing the ACME TXT record
## Ref. https://go-acme.github.io/lego/dns/azuredns/index.html#azure-managed-identity-with-azure-workload
resource "azurerm_role_assignment" "custom_zone_read" {
  scope                = azurerm_dns_zone.custom_zone.id
  role_definition_name = "Reader"
  principal_id         = var.principal_id
}
resource "azurerm_role_assignment" "custom_zone_manage_acme_assets_txt_record" {
  scope                = "${azurerm_dns_zone.custom_zone.id}/TXT/_acme-challenge.assets"
  role_definition_name = "DNS Zone Contributor"
  principal_id         = var.principal_id
}
resource "azurerm_role_assignment" "custom_zone_manage_acme_txt_record" {
  scope                = "${azurerm_dns_zone.custom_zone.id}/TXT/_acme-challenge"
  role_definition_name = "DNS Zone Contributor"
  principal_id         = var.principal_id
}
