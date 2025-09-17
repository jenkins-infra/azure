resource "azurerm_resource_group" "get_jenkins_io" {
  name     = "get-jenkins-io"
  location = var.location
  tags     = local.default_tags
}
