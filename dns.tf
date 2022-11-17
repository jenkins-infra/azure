data "azurerm_resource_group" "proddns_jenkinsio" {
  name = "proddns_jenkinsio"
}

data "azurerm_dns_zone" "jenkinsio" {
  name = "jenkins.io"
}
