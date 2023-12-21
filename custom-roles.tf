resource "azurerm_role_definition" "private_vnet_reader" {
  name  = "ReadPrivateVNET"
  scope = data.azurerm_virtual_network.private.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}

resource "azurerm_role_definition" "public_vnet_reader" {
  name  = "ReadPublicVNET"
  scope = data.azurerm_virtual_network.public.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}

