output "ephemeral_agents_nsg_rg_name" {
  value = azurerm_network_security_group.ephemeral_agents.resource_group_name
}

output "ephemeral_agents_nsg_name" {
  value = azurerm_network_security_group.ephemeral_agents.name
}

output "ephemeral_agents_resource_group_name" {
  value = azurerm_resource_group.ephemeral_agents.name
}

output "ephemeral_agents_network_rg_name" {
  value = var.ephemeral_agents_network_rg_name
}

output "ephemeral_agents_network_name" {
  value = var.ephemeral_agents_network_name
}

output "ephemeral_agents_subnet_name" {
  value = var.ephemeral_agents_subnet_name
}

output "ephemeral_agents_storage_account_name" {
  value = azurerm_storage_account.ephemeral_agents.name
}
