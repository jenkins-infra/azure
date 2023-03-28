resource "azurerm_role_definition" "private_vnet_reader" {
  name  = "ReadPrivateVNET"
  scope = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private.name}"

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}

resource "azurerm_role_definition" "public_vnet_reader" {
  name  = "ReadPublicVNET"
  scope = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.public.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.public.name}"

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
