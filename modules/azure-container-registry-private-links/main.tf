data "azurerm_container_registry" "dockerhub_mirror" {
  provider            = azurerm.acr
  name                = var.acr_name
  resource_group_name = var.acr_rg_name
}

data "azurerm_virtual_network" "target" {
  provider            = azurerm
  name                = var.vnet_name
  resource_group_name = var.vnet_rg_name
}

data "azurerm_subnet" "target" {
  provider             = azurerm
  name                 = var.subnet_name
  resource_group_name  = var.vnet_rg_name
  virtual_network_name = data.azurerm_virtual_network.target.name
}

resource "azurerm_private_endpoint" "dockerhub_mirror" {
  provider = azurerm
  name     = "acr-${var.name}"

  location            = data.azurerm_virtual_network.target.location
  resource_group_name = data.azurerm_virtual_network.target.resource_group_name
  subnet_id           = data.azurerm_subnet.target.id

  custom_network_interface_name = "acr-${var.name}-nic"

  private_service_connection {
    name                           = "acr-${var.name}"
    private_connection_resource_id = data.azurerm_container_registry.dockerhub_mirror.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    # Conventional and static name required by Azure (otherwise automatic record creation does not work)
    name                 = "privatelink.azurecr.io"
    private_dns_zone_ids = [azurerm_private_dns_zone.dockerhub_mirror.id]
  }
  tags = var.default_tags
}

resource "azurerm_private_dns_zone" "dockerhub_mirror" {
  provider = azurerm
  # Conventional and static name required by Azure (otherwise automatic record creation does not work)
  name = "privatelink.azurecr.io"

  # Private DNS zone name is static: we can only have one per RG
  resource_group_name = data.azurerm_virtual_network.target.resource_group_name

  tags = var.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dockerhub_mirror" {
  provider = azurerm
  # Private DNS zone name is static: we can only have one per RG
  name                  = "privatelink.azurecr.io"
  resource_group_name   = data.azurerm_virtual_network.target.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.dockerhub_mirror.name
  virtual_network_id    = data.azurerm_virtual_network.target.id

  registration_enabled = true
  tags                 = var.default_tags
}
