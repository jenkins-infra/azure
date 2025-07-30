# The resources groups and virtual networks below are defined here:
# https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf

################################################################################
## Resource Groups
################################################################################
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_resource_group" "public" {
  name = "public"
}
data "azurerm_resource_group" "private" {
  name = "private"
}
data "azurerm_resource_group" "infra_ci_jenkins_io" {
  name = "infra-ci-jenkins-io"
}
data "azurerm_resource_group" "cert_ci_jenkins_io" {
  name = "cert-ci-jenkins-io"
}
data "azurerm_resource_group" "trusted_ci_jenkins_io" {
  name = "trusted-ci-jenkins-io"
}

################################################################################
## Virtual Networks
################################################################################
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vnets.tf
data "azurerm_virtual_network" "public" {
  name                = "${data.azurerm_resource_group.public.name}-vnet"
  resource_group_name = data.azurerm_resource_group.public.name
}
data "azurerm_virtual_network" "private" {
  name                = "${data.azurerm_resource_group.private.name}-vnet"
  resource_group_name = data.azurerm_resource_group.private.name
}
# Reference to the PostgreSQL/MySql dedicated network external resources
data "azurerm_virtual_network" "public_db" {
  name                = "${data.azurerm_resource_group.public.name}-db-vnet"
  resource_group_name = data.azurerm_resource_group.public.name
}
data "azurerm_virtual_network" "infra_ci_jenkins_io" {
  name                = "${data.azurerm_resource_group.infra_ci_jenkins_io.name}-vnet"
  resource_group_name = data.azurerm_resource_group.infra_ci_jenkins_io.name
}
data "azurerm_virtual_network" "cert_ci_jenkins_io" {
  name                = "${data.azurerm_resource_group.cert_ci_jenkins_io.name}-vnet"
  resource_group_name = data.azurerm_resource_group.cert_ci_jenkins_io.name
}
data "azurerm_virtual_network" "trusted_ci_jenkins_io" {
  name                = "trusted-ci-jenkins-io-vnet"
  resource_group_name = data.azurerm_resource_group.trusted_ci_jenkins_io.name
}

################################################################################
## SUB NETWORKS
################################################################################
# Defined in https://github.com/jenkins-infra/azure-net/blob/main/vpn.tf
data "azurerm_subnet" "private_vnet_data_tier" {
  name                 = "${data.azurerm_virtual_network.private.name}-data-tier"
  virtual_network_name = data.azurerm_virtual_network.private.name
  resource_group_name  = data.azurerm_resource_group.private.name
}
data "azurerm_subnet" "infra_ci_jenkins_io_ephemeral_agents" {
  name                 = "${data.azurerm_virtual_network.infra_ci_jenkins_io.name}-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.infra_ci_jenkins_io.name
  resource_group_name  = data.azurerm_virtual_network.infra_ci_jenkins_io.resource_group_name
}
data "azurerm_subnet" "infracijenkinsio_agents_2" {
  name                 = "${data.azurerm_virtual_network.infra_ci_jenkins_io.name}-kubernetes-agents"
  resource_group_name  = data.azurerm_virtual_network.infra_ci_jenkins_io.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.infra_ci_jenkins_io.name
}
data "azurerm_subnet" "cert_ci_jenkins_io_controller" {
  name                 = "${data.azurerm_virtual_network.cert_ci_jenkins_io.name}-controller"
  virtual_network_name = data.azurerm_virtual_network.cert_ci_jenkins_io.name
  resource_group_name  = data.azurerm_virtual_network.cert_ci_jenkins_io.resource_group_name
}
data "azurerm_subnet" "cert_ci_jenkins_io_ephemeral_agents" {
  name                 = "${data.azurerm_virtual_network.cert_ci_jenkins_io.name}-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.cert_ci_jenkins_io.name
  resource_group_name  = data.azurerm_virtual_network.cert_ci_jenkins_io.resource_group_name
}
data "azurerm_subnet" "trusted_ci_jenkins_io_controller" {
  name                 = "${data.azurerm_virtual_network.trusted_ci_jenkins_io.name}-controller"
  virtual_network_name = data.azurerm_virtual_network.trusted_ci_jenkins_io.name
  resource_group_name  = data.azurerm_resource_group.trusted_ci_jenkins_io.name
}
data "azurerm_subnet" "trusted_ci_jenkins_io_permanent_agents" {
  name                 = "${data.azurerm_virtual_network.trusted_ci_jenkins_io.name}-permanent-agents"
  virtual_network_name = data.azurerm_virtual_network.trusted_ci_jenkins_io.name
  resource_group_name  = data.azurerm_resource_group.trusted_ci_jenkins_io.name
}
data "azurerm_subnet" "trusted_ci_jenkins_io_ephemeral_agents" {
  name                 = "${data.azurerm_virtual_network.trusted_ci_jenkins_io.name}-ephemeral-agents"
  resource_group_name  = data.azurerm_resource_group.trusted_ci_jenkins_io.name
  virtual_network_name = data.azurerm_virtual_network.trusted_ci_jenkins_io.name
}
data "azurerm_subnet" "infra_ci_jenkins_io_packer_builds" {
  name                 = "${data.azurerm_virtual_network.infra_ci_jenkins_io.name}-packer-builds"
  virtual_network_name = data.azurerm_virtual_network.infra_ci_jenkins_io.name
  resource_group_name  = data.azurerm_virtual_network.infra_ci_jenkins_io.resource_group_name
}
data "azurerm_subnet" "privatek8s_tier" {
  name                 = "privatek8s-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}
data "azurerm_subnet" "privatek8s_release_tier" {
  name                 = "privatek8s-release-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}
data "azurerm_subnet" "privatek8s_infra_ci_controller_tier" {
  name                 = "privatek8s-infraci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}
data "azurerm_subnet" "privatek8s_release_ci_controller_tier" {
  name                 = "privatek8s-releaseci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}


#### TODO: remove resources below as part of cleanup in https://github.com/jenkins-infra/helpdesk/issues/4690
data "azurerm_resource_group" "private_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "private-sponsorship"
}
data "azurerm_virtual_network" "private_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "${data.azurerm_resource_group.private_sponsorship.name}-vnet"
  resource_group_name = data.azurerm_resource_group.private_sponsorship.name
}
data "azurerm_subnet" "privatek8s_sponsorship_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-tier"
  resource_group_name  = data.azurerm_resource_group.private_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.private_sponsorship.name
}
####
