output "private_endpoint_nic_ip_addresses" {
  value = join(",",
    distinct(
      flatten(
        [for rs in azurerm_private_endpoint.dockerhub_mirror.private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
      )
    )
  )
}

output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.dockerhub_mirror.id
}

output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.dockerhub_mirror.name
}

output "private_dns_zone_resource_group_name" {
  value = azurerm_private_dns_zone.dockerhub_mirror.resource_group_name
}
