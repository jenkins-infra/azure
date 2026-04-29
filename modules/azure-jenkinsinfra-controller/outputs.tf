output "controller_resourcegroup_name" {
  value = azurerm_resource_group.controller.name
}

output "controller_public_ipv4" {
  value = var.is_public ? azurerm_public_ip.controller[0].ip_address : azurerm_linux_virtual_machine.controller.private_ip_address
}

output "controller_public_ipv6" {
  value = var.is_public && var.enable_public_ipv6 ? azurerm_public_ip.controller_ipv6[0].ip_address : ""
}

output "controller_private_ipv4" {
  value = azurerm_linux_virtual_machine.controller.private_ip_address
}

output "controller_public_fqdn" {
  value = length(azurerm_dns_a_record.controller) == 1 ? azurerm_dns_a_record.controller[0].fqdn : var.service_fqdn
}

output "controller_private_fqdn" {
  value = length(azurerm_dns_a_record.private_controller) == 1 ? azurerm_dns_a_record.private_controller[0].fqdn : var.service_fqdn
}

output "service_fqdn" {
  value = var.service_fqdn
}

output "controller_nsg_name" {
  value = azurerm_network_security_group.controller.name
}

output "controller_nsg_id" {
  value = azurerm_network_security_group.controller.id
}

output "service_short_name" {
  value = local.service_short_name
}

output "service_short_stripped_name" {
  value = local.service_short_stripped_name
}

output "controller_service_principal_id" {
  value = local.controller_principal_id
}
