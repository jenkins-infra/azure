resource "azurerm_role_definition" "private_vnet_reader" {
  name  = "ReadPrivateVNET"
  scope = data.azurerm_virtual_network.private.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}

resource "azurerm_role_definition" "prod_public_vnet_reader" {
  name  = "ReadProdPublicVNET"
  scope = data.azurerm_virtual_network.public_prod.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
