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

# Managed in jenkins-infra/azure-net for the letsencrypt IDP
data "azurerm_dns_zone" "trusted_ci_jenkins_io" {
  name                = "trusted.ci.jenkins.io"
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
}
# Managed in jenkins-infra/azure-net for the letsencrypt IDP
data "azurerm_dns_zone" "cert_ci_jenkins_io" {
  name                = "cert.ci.jenkins.io"
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
}
