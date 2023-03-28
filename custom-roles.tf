resource "azurerm_role_definition" "private_vnet_reader" {
  name  = "ReadPrivateVNET"
  scope = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private.name}"

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}

resource "azurerm_role_definition" "prod_public_vnet_reader" {
  name  = "ReadProdPublicVNET"
  scope = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.public_prod.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.public_prod.name}"

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
