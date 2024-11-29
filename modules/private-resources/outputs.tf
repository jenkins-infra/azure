output "zone_name" {
  value = var.dns_zone_name == "" ? azurerm_private_dns_zone.dnszone[0].name : data.azurerm_private_dns_zone.existing_dnszone[0].name
}

output "zone_id" {
  value = var.dns_zone_name == "" ? azurerm_private_dns_zone.dnszone[0].id : data.azurerm_private_dns_zone.existing_dnszone[0].id
}

output "endpoint_ip" {
  value = azurerm_private_endpoint.pe.private_service_connection[0].private_ip_address
}
