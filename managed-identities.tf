resource "azurerm_resource_group" "accounts" {
  name     = "managed-identities"
  location = var.location
  tags = local.default_tags
}

# To be used by updatecli for listing resources like OS image versions for example
resource "azurerm_user_assigned_identity" "updatecli" {
  name                = "updatecli"
  location            = azurerm_resource_group.accounts.location
  resource_group_name = azurerm_resource_group.accounts.name
}
