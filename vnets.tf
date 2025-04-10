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
data "azurerm_resource_group" "private_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "private-sponsorship"
}
data "azurerm_resource_group" "public_jenkins_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "public-jenkins-sponsorship"
}
data "azurerm_resource_group" "infra_ci_jenkins_io_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "infra-ci-jenkins-io-sponsorship"
}
data "azurerm_resource_group" "cert_ci_jenkins_io" {
  name = "cert-ci-jenkins-io"
}
data "azurerm_resource_group" "cert_ci_jenkins_io_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "cert-ci-jenkins-io-sponsorship"
}
data "azurerm_resource_group" "trusted_ci_jenkins_io" {
  name = "trusted-ci-jenkins-io"
}
data "azurerm_resource_group" "trusted_ci_jenkins_io_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "trusted-ci-jenkins-io-sponsorship"
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
data "azurerm_virtual_network" "private_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "${data.azurerm_resource_group.private_sponsorship.name}-vnet"
  resource_group_name = data.azurerm_resource_group.private_sponsorship.name
}
data "azurerm_virtual_network" "public_jenkins_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "${data.azurerm_resource_group.public_jenkins_sponsorship.name}-vnet"
  resource_group_name = data.azurerm_resource_group.public_jenkins_sponsorship.name
}
# Reference to the PostgreSQL/MySql dedicated network external resources
data "azurerm_virtual_network" "public_db" {
  name                = "${data.azurerm_resource_group.public.name}-db-vnet"
  resource_group_name = data.azurerm_resource_group.public.name
}
data "azurerm_virtual_network" "infra_ci_jenkins_io_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "${data.azurerm_resource_group.infra_ci_jenkins_io_sponsorship.name}-vnet"
  resource_group_name = data.azurerm_resource_group.infra_ci_jenkins_io_sponsorship.name
}
data "azurerm_virtual_network" "cert_ci_jenkins_io" {
  name                = "${data.azurerm_resource_group.cert_ci_jenkins_io.name}-vnet"
  resource_group_name = data.azurerm_resource_group.cert_ci_jenkins_io.name
}
data "azurerm_virtual_network" "cert_ci_jenkins_io_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "${data.azurerm_resource_group.cert_ci_jenkins_io_sponsorship.name}-vnet"
  resource_group_name = data.azurerm_resource_group.cert_ci_jenkins_io_sponsorship.name
}
data "azurerm_virtual_network" "trusted_ci_jenkins_io" {
  name                = "trusted-ci-jenkins-io-vnet"
  resource_group_name = data.azurerm_resource_group.trusted_ci_jenkins_io.name
}
data "azurerm_virtual_network" "trusted_ci_jenkins_io_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "${data.azurerm_resource_group.trusted_ci_jenkins_io_sponsorship.name}-vnet"
  resource_group_name = data.azurerm_resource_group.trusted_ci_jenkins_io_sponsorship.name
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
data "azurerm_subnet" "infra_ci_jenkins_io_sponsorship_ephemeral_agents" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name}-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.resource_group_name
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
data "azurerm_subnet" "cert_ci_jenkins_io_sponsorship_ephemeral_agents" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.cert_ci_jenkins_io_sponsorship.name}-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsorship.resource_group_name
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
data "azurerm_subnet" "trusted_ci_jenkins_io_sponsorship_ephemeral_agents" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsorship.name}-ephemeral-agents"
  virtual_network_name = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.trusted_ci_jenkins_io_sponsorship.resource_group_name
}
data "azurerm_subnet" "infra_ci_jenkins_io_sponsorship_packer_builds" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name}-packer-builds"
  virtual_network_name = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.resource_group_name
}
data "azurerm_subnet" "ci_jenkins_io_controller_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.public_jenkins_sponsorship.name}-ci_jenkins_io_controller"
  virtual_network_name = data.azurerm_virtual_network.public_jenkins_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.public_jenkins_sponsorship.resource_group_name
}
data "azurerm_subnet" "ci_jenkins_io_ephemeral_agents_jenkins_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.public_jenkins_sponsorship.name}-ci_jenkins_io_agents"
  virtual_network_name = data.azurerm_virtual_network.public_jenkins_sponsorship.name
  resource_group_name  = data.azurerm_virtual_network.public_jenkins_sponsorship.resource_group_name
}
data "azurerm_subnet" "ci_jenkins_io_kubernetes_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.public_jenkins_sponsorship.name}-ci_jenkins_io_kubernetes"
  resource_group_name  = data.azurerm_resource_group.public_jenkins_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.public_jenkins_sponsorship.name
}
data "azurerm_subnet" "privatek8s_sponsorship_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-tier"
  resource_group_name  = data.azurerm_resource_group.private_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.private_sponsorship.name
}
data "azurerm_subnet" "privatek8s_sponsorship_release_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-release-tier"
  resource_group_name  = data.azurerm_resource_group.private_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.private_sponsorship.name
}
data "azurerm_subnet" "privatek8s_sponsorship_infra_ci_controller_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-infraci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.private_sponsorship.name
}
data "azurerm_subnet" "privatek8s_sponsorship_release_ci_controller_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-releaseci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.private_sponsorship.name
}
