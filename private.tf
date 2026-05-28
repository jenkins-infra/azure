# Allow access to the private Azure Container Registry through an Azure Endpoint NIC
module "private_acr_pe" {
  source = "./modules/azure-container-registry-private-links"

  providers = {
    azurerm     = azurerm
    azurerm.acr = azurerm
  }

  name = "private"

  acr_name     = azurerm_container_registry.dockerhub_mirror.name
  acr_location = azurerm_container_registry.dockerhub_mirror.location
  acr_rg_name  = azurerm_container_registry.dockerhub_mirror.resource_group_name

  subnet_name  = data.azurerm_subnet.private_vnet_data_tier.name
  vnet_name    = data.azurerm_virtual_network.private.name
  vnet_rg_name = data.azurerm_virtual_network.private.resource_group_name

  default_tags = local.default_tags
}
