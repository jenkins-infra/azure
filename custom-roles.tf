resource "azurerm_role_definition" "private_sponsorship_vnet_reader" {
  provider = azurerm.jenkins-sponsorship
  name     = "ReadPrivateSponsorshipVNET"
  scope    = data.azurerm_virtual_network.private_sponsorship.id

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
