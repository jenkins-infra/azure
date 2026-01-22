output "zone_name" {
  value = azurerm_dns_zone.custom_zone.name
}

output "zone_rg_name" {
  value = azurerm_dns_zone.custom_zone.resource_group_name
}
