resource "azurerm_resource_group" "cijenkinsio_kubernetes_agents" {
  provider = azurerm.jenkins-sponsorship
  name     = "ci-jenkins-io-kubernetes-agents"
  location = var.location
  tags     = local.default_tags
}

data "azurerm_subnet" "ci_jenkins_io_kubernetes_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "${data.azurerm_virtual_network.public_jenkins_sponsorship.name}-ci_jenkins_io_kubernetes"
  resource_group_name  = data.azurerm_resource_group.public_jenkins_sponsorship.name
  virtual_network_name = data.azurerm_virtual_network.public_jenkins_sponsorship.name
}

#trivy:ignore:avd-azu-0040 # No need to enable oms_agent for Azure monitoring as we already have datadog
resource "azurerm_kubernetes_cluster" "cijenkinsio_agents_1" {
  provider = azurerm.jenkins-sponsorship
  name     = local.aks_clusters["cijenkinsio_agents_1"].name
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - ci.jenkins.io controller to allow spawning agents (nominal usage)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = "cijenkinsioagents1" # Avoid hyphens in this DNS host
  location                            = azurerm_resource_group.cijenkinsio_kubernetes_agents.location
  resource_group_name                 = azurerm_resource_group.cijenkinsio_kubernetes_agents.name
  kubernetes_version                  = local.aks_clusters["cijenkinsio_agents_1"].kubernetes_version
  role_based_access_control_enabled   = true # default value but made explicit to please trivy

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard" # Required to customize the outbound type
    pod_cidr            = local.ci_jenkins_io_agents_1_pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "systempool1"
    only_critical_addons_enabled = true                # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2pds_v5" # At least 4 vCPUS/4 Gb as per AKS best practices
    temporary_name_for_rotation  = "syspooltemp"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "AzureLinux"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 75 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
    orchestrator_version = local.aks_clusters["cijenkinsio_agents_1"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id
    tags                 = local.default_tags
    # Avoid deploying system pool in the same zone as other node pools
    zones = [for zone in local.cijenkinsio_agents_1_compute_zones : zone + 1]
  }

  tags = local.default_tags
}

# Node pool to host "jenkins-infra" applications required on this cluster such as ACP or datadog's cluster-agent, e.g. "Not agent, neither AKS System tools"
resource "azurerm_kubernetes_cluster_node_pool" "linux_arm64_n2_applications" {
  provider = azurerm.jenkins-sponsorship
  name     = "la64n2app"
  vm_size  = "Standard_D4pds_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["cijenkinsio_agents_1"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 3 # 2 nodes always up for HA, a 3rd one is allowed for surge upgrades
  zones                 = local.cijenkinsio_agents_1_compute_zones
  vnet_subnet_id        = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id

  node_labels = {
    "jenkins" = "ci.jenkins.io"
    "role"    = "applications"
  }
  node_taints = [
    "ci.jenkins.io/applications=true:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Node pool to host ci.jenkins.io agents for usual builds
resource "azurerm_kubernetes_cluster_node_pool" "linux_x86_64_n4_agents_1" {
  provider = azurerm.jenkins-sponsorship
  name     = "lx86n3agt1"
  vm_size  = "Standard_D16ads_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 600 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["cijenkinsio_agents_1"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 40 # 3 pods per nodes, max 120 pods - due to quotas
  zones                 = local.cijenkinsio_agents_1_compute_zones
  vnet_subnet_id        = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id

  node_labels = {
    "jenkins" = "ci.jenkins.io"
    "role"    = "jenkins-agents"
  }
  node_taints = [
    "ci.jenkins.io/agents=true:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Node pool to host ci.jenkins.io agents for BOM builds
resource "azurerm_kubernetes_cluster_node_pool" "linux_x86_64_n4_bom_1" {
  provider = azurerm.jenkins-sponsorship
  name     = "lx86n3bom1"
  vm_size  = "Standard_D16ads_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 600 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["cijenkinsio_agents_1"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 50
  zones                 = local.cijenkinsio_agents_1_compute_zones
  vnet_subnet_id        = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id

  node_labels = {
    "jenkins" = "ci.jenkins.io"
    "role"    = "jenkins-agents-bom"
  }
  node_taints = [
    "ci.jenkins.io/agents=true:NoSchedule",
    "ci.jenkins.io/bom=true:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Allow AKS to manipulate LBs, PLS and join subnets - https://learn.microsoft.com/en-us/azure/aks/internal-lb?tabs=set-service-annotations#use-private-networks (see Note)
resource "azurerm_role_assignment" "cijio_agents_networkcontributor_vnet" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = data.azurerm_virtual_network.public_jenkins_sponsorship.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.cijenkinsio_agents_1.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "cijenkinsio_agents_1_admin_sa" {
  providers = {
    kubernetes = kubernetes.cijenkinsio_agents_1
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.cijenkinsio_agents_1.name
  cluster_hostname           = azurerm_kubernetes_cluster.cijenkinsio_agents_1.fqdn
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.cluster_ca_certificate
}
output "kubeconfig_cijenkinsio_agents_1" {
  sensitive = true
  value     = module.cijenkinsio_agents_1_admin_sa.kubeconfig
}
output "cijenkinsio_agents_1_kube_config_command" {
  value = "az aks get-credentials --name ${azurerm_kubernetes_cluster.cijenkinsio_agents_1.name} --resource-group ${azurerm_kubernetes_cluster.cijenkinsio_agents_1.resource_group_name}"
}
