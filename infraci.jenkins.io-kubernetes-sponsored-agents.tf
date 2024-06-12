resource "azurerm_resource_group" "infracijio_kubernetes_agents_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "infra-ci-jenkins-io-kubernetes-agents"
  location = var.location
  tags     = local.default_tags
}

data "azurerm_subnet" "infraci_jenkins_io_kubernetes_agent_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name}-kubernetes-agents"
  resource_group_name  = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.name
}

#trivy:ignore:avd-azu-0040 # No need to enable oms_agent for Azure monitoring as we already have datadog
resource "azurerm_kubernetes_cluster" "infracijenkinsio_agents_1" {
  provider = azurerm.jenkins-sponsorship
  name     = "infracijenkinsio-agents-1"
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = "infracijenkinsioagents1" # Avoid hyphens in this DNS host
  location                            = azurerm_resource_group.infracijio_kubernetes_agents_sponsorship.location
  resource_group_name                 = azurerm_resource_group.infracijio_kubernetes_agents_sponsorship.name
  kubernetes_version                  = local.kubernetes_versions["infracijenkinsio_agents_1"]
  role_based_access_control_enabled   = true # default value but made explicit to please trivy

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard" # Required to customize the outbound type
    pod_cidr            = local.infraci_jenkins_io_agents_1_pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "systempool1"
    only_critical_addons_enabled = true                # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D4pds_v5" # At least 4 vCPUS/4 Gb as per AKS best practises
    os_sku                       = "AzureLinux"
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 150 # Ref. Cache storage size athttps://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
    orchestrator_version         = local.kubernetes_versions["infracijenkinsio_agents_1"]
    kubelet_disk_type            = "OS"
    enable_auto_scaling          = false
    node_count                   = 3 # 3 nodes for HA as per AKS best practises
    vnet_subnet_id               = data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id
    tags                         = local.default_tags
    zones                        = local.infracijenkinsio_agents_1_compute_zones
  }

  tags = local.default_tags
}

# Node pool to host infra.ci.jenkins.io x86_64 agents
# number of pods per node calculated with https://github.com/jenkins-infra/kubernetes-management/blob/9c14f72867170e9755f3434fb6f6dd3a8606686a/config/jenkins_infra.ci.jenkins.io.yaml#L137-L208
resource "azurerm_kubernetes_cluster_node_pool" "linux_x86_64_agents_1_sponsorship" {
  provider              = azurerm.jenkins-sponsorship
  name                  = "lx86n14agt1"
  vm_size               = "Standard_D8ads_v5" # https://learn.microsoft.com/en-us/azure/virtual-machines/dasv5-dadsv5-series Standard_D8ads_v5 	8vcpu 	32Go 	300ssd
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 300 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dasv5-dadsv5-series (depends on the instance size)
  orchestrator_version  = local.kubernetes_versions["infracijenkinsio_agents_1"]
  kubernetes_cluster_id = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 20
  zones                 = local.infracijenkinsio_agents_1_compute_zones
  vnet_subnet_id        = data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id

  node_labels = {
    "jenkins" = "infra.ci.jenkins.io"
    "role"    = "jenkins-agents"
  }
  node_taints = [
    "infra.ci.jenkins.io/agents=true:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# # Node pool to host infra.ci.jenkins.io
# number of pods per node calculated with https://github.com/jenkins-infra/kubernetes-management/blob/9c14f72867170e9755f3434fb6f6dd3a8606686a/config/jenkins_infra.ci.jenkins.io.yaml#L137-L208
resource "azurerm_kubernetes_cluster_node_pool" "linux_arm64_agents_1_sponsorship" {
  provider              = azurerm.jenkins-sponsorship
  name                  = "la64n14agt1"
  vm_size               = "Standard_D8pds_v5" # https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series 	8vcpu 	32Go 	300ssd
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 300 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.kubernetes_versions["infracijenkinsio_agents_1"]
  kubernetes_cluster_id = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 20
  zones                 = local.infracijenkinsio_agents_1_compute_zones # need to be on zone 1 for arm availability
  vnet_subnet_id        = data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id

  node_labels = {
    "jenkins" = "infra.ci.jenkins.io"
    "role"    = "jenkins-agents"
  }
  node_taints = [
    "infra.ci.jenkins.io/agents=true:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "infracijenkinsio_agents_1_admin_sa_sponsorship" {
  providers = {
    kubernetes = kubernetes.infracijenkinsio_agents_1
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.name
  cluster_hostname           = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.fqdn
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.kube_config.0.cluster_ca_certificate
}
output "kubeconfig_infracijenkinsio_agents_1" {
  sensitive = true
  value     = module.infracijenkinsio_agents_1_admin_sa_sponsorship.kubeconfig
}
output "infracijenkinsio_agents_1_kube_config_command" {
  value = "az aks get-credentials --name ${azurerm_kubernetes_cluster.infracijenkinsio_agents_1.name} --resource-group ${azurerm_kubernetes_cluster.infracijenkinsio_agents_1.resource_group_name}"
}
