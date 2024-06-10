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
