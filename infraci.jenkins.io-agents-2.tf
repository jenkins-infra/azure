resource "azurerm_resource_group" "infracijenkinsio_agents_2" {
  name     = local.aks_clusters["infracijenkinsio_agents_2"].name
  location = var.location
  tags     = local.default_tags
}

#trivy:ignore:avd-azu-0040 # No need to enable oms_agent for Azure monitoring as we already have datadog
resource "azurerm_kubernetes_cluster" "infracijenkinsio_agents_2" {
  name     = local.aks_clusters["infracijenkinsio_agents_2"].name
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = "infracijenkinsioagents2" # Avoid hyphens in this DNS host
  location                            = azurerm_resource_group.infracijenkinsio_agents_2.location
  resource_group_name                 = azurerm_resource_group.infracijenkinsio_agents_2.name
  kubernetes_version                  = local.aks_clusters["infracijenkinsio_agents_2"].kubernetes_version
  # default value but made explicit to please trivy
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard" # Required to customize the outbound type
    pod_cidr            = local.aks_clusters.infracijenkinsio_agents_2.pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "systempool1"
    only_critical_addons_enabled = true # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2pds_v5"
    temporary_name_for_rotation  = "syspooltemp"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "AzureLinux"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 75 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
    orchestrator_version = local.aks_clusters["infracijenkinsio_agents_2"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.infracijenkinsio_agents_2.id
    tags                 = local.default_tags
    zones                = local.aks_clusters.compute_zones.system_pool
  }

  tags = local.default_tags
}

# Node pool to host infra.ci.jenkins.io x86_64 agents
# number of pods per node calculated with https://github.com/jenkins-infra/kubernetes-management/blob/9c14f72867170e9755f3434fb6f6dd3a8606686a/config/jenkins_infra.ci.jenkins.io.yaml#L137-L208
resource "azurerm_kubernetes_cluster_node_pool" "infracijenkinsio_agents_2_linux_x86_64_agents_1" {
  name                  = "lx86n14agt1"
  vm_size               = "Standard_D8ads_v5" # https://learn.microsoft.com/en-us/azure/virtual-machines/dasv5-dadsv5-series Standard_D8ads_v5 	8vcpu 	32Go 	300ssd
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 300 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dasv5-dadsv5-series (depends on the instance size)
  priority              = "Spot"
  eviction_policy       = "Delete" # Ref Not on priority https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool
  spot_max_price        = -1       # Ref Not on priority https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool
  orchestrator_version  = local.aks_clusters["infracijenkinsio_agents_2"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.infracijenkinsio_agents_2.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 20
  zones                 = local.aks_clusters.compute_zones.amd64_pool
  vnet_subnet_id        = data.azurerm_subnet.infracijenkinsio_agents_2.id

  node_labels = {
    "jenkins"                               = "infra.ci.jenkins.io"
    "role"                                  = "jenkins-agents"
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  node_taints = [
    "infra.ci.jenkins.io/agents=true:NoSchedule",
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# # Node pool to host infra.ci.jenkins.io arm64 agents
# number of pods per node calculated with https://github.com/jenkins-infra/kubernetes-management/blob/9c14f72867170e9755f3434fb6f6dd3a8606686a/config/jenkins_infra.ci.jenkins.io.yaml#L137-L208
resource "azurerm_kubernetes_cluster_node_pool" "infracijenkinsio_agents_2_linux_arm64_agents_2" {

  name                  = "la64n14agt2"
  vm_size               = "Standard_D16pds_v5" # temporarily upgrade https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dpdsv5-series?tabs=sizebasic 	16vcpu 	64Go 	600ssd
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 600 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dpdsv5-series?tabs=sizebasic (depends on the instance size)
  priority              = "Spot"
  eviction_policy       = "Delete" # Ref Not on priority https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool
  spot_max_price        = -1       # Ref Not on priority https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool
  orchestrator_version  = local.aks_clusters["infracijenkinsio_agents_2"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.infracijenkinsio_agents_2.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 20
  zones                 = local.aks_clusters.compute_zones.arm64_pool
  vnet_subnet_id        = data.azurerm_subnet.infracijenkinsio_agents_2.id

  node_labels = {
    "jenkins"                               = "infra.ci.jenkins.io"
    "role"                                  = "jenkins-agents"
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  node_taints = [
    "infra.ci.jenkins.io/agents=true:NoSchedule",
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}
resource "kubernetes_namespace" "infracijenkinsio_agents_2_infra_ci_jenkins_io_agents" {
  provider = kubernetes.infracijenkinsio_agents_2

  metadata {
    name = "jenkins-infra-agents"
    labels = {
      name = "jenkins-infra-agents"
    }
  }
}
resource "kubernetes_service_account" "infracijenkinsio_agents_2_infra_ci_jenkins_io_agents" {
  provider = kubernetes.infracijenkinsio_agents_2

  metadata {
    name      = "jenkins-infra-agent"
    namespace = kubernetes_namespace.infracijenkinsio_agents_2_infra_ci_jenkins_io_agents.metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents.client_id
    }
  }
}
resource "azurerm_federated_identity_credential" "infracijenkinsio_agents_2_infra_ci_jenkins_io_agents" {
  name                = "infracijenkinsio-agents-2-${kubernetes_service_account.infracijenkinsio_agents_2_infra_ci_jenkins_io_agents.metadata[0].name}"
  resource_group_name = azurerm_kubernetes_cluster.infracijenkinsio_agents_2.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.infracijenkinsio_agents_2.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents.id
  subject             = "system:serviceaccount:${kubernetes_namespace.infracijenkinsio_agents_2_infra_ci_jenkins_io_agents.metadata[0].name}:${kubernetes_service_account.infracijenkinsio_agents_2_infra_ci_jenkins_io_agents.metadata[0].name}"
}

#Configure the jenkins-infra/kubernetes-management admin service account
module "infracijenkinsio_agents_2_admin_sa" {
  providers = {
    kubernetes = kubernetes.infracijenkinsio_agents_2
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.infracijenkinsio_agents_2.name
  cluster_hostname           = local.aks_clusters_outputs.infracijenkinsio_agents_2.cluster_hostname
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.infracijenkinsio_agents_2.kube_config.0.cluster_ca_certificate
}
output "kubeconfig_management_infracijenkinsio_agents_2" {
  sensitive = true
  value     = module.infracijenkinsio_agents_2_admin_sa.kubeconfig
}
