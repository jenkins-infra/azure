resource "azurerm_resource_group" "packer-images" {
  name     = "${var.prefix}-packer-images"
  location = var.location

  tags = {
    env = var.prefix
  }
}
