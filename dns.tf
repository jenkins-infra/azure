# Jenkins.io DNS zone
data "azurerm_resource_group" "proddns_jenkinsio" {
  name = "proddns_jenkinsio"
}
data "azurerm_dns_zone" "jenkinsio" {
  name                = "jenkins.io"
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
}

# Jenkins-ci.org DNS zone
data "azurerm_resource_group" "proddns_jenkinsci" {
  name = "proddns_jenkinsci"
}
data "azurerm_dns_zone" "jenkinsciorg" {
  name                = "jenkins-ci.org"
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsci.name
}
