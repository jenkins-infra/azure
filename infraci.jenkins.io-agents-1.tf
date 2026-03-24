resource "azurerm_resource_group" "infracijenkinsio_agents_1" {
  provider = azurerm.jenkins-sponsored
  name     = local.aks_clusters["infracijenkinsio_agents_1"].name
  location = var.location
  tags     = local.default_tags
}

#trivy:ignore:avd-azu-0040 # No need to enable oms_agent for Azure monitoring as we already have datadog
resource "azurerm_kubernetes_cluster" "infracijenkinsio_agents_1" {
  provider = azurerm.jenkins-sponsored
  name     = local.aks_clusters["infracijenkinsio_agents_1"].name
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = "infracijenkinsioagents1" # Avoid hyphens in this DNS host
  location                            = azurerm_resource_group.infracijenkinsio_agents_1.location
  resource_group_name                 = azurerm_resource_group.infracijenkinsio_agents_1.name
  kubernetes_version                  = local.aks_clusters["infracijenkinsio_agents_1"].kubernetes_version
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
    pod_cidr            = local.aks_clusters.infracijenkinsio_agents_1.pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "systempool1"
    only_critical_addons_enabled = true # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2pds_v6"
    temporary_name_for_rotation  = "syspooltemp"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "AzureLinux"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 100 # Expecting an ephemeral OS disk. Specified size must be less than the instance local storage size. Ref. https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dpdsv6-series?tabs=sizestoragelocal
    orchestrator_version = local.aks_clusters["infracijenkinsio_agents_1"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.infra_ci_jenkins_io_sponsored_kubernetes_agents.id
    tags                 = local.default_tags
    zones                = local.aks_clusters.compute_zones_sponsored.system_pool
  }

  tags = local.default_tags
}

# Node pool to host infra.ci.jenkins.io x86_64 agents
# number of pods per node calculated with https://github.com/jenkins-infra/kubernetes-management/blob/9c14f72867170e9755f3434fb6f6dd3a8606686a/config/jenkins_infra.ci.jenkins.io.yaml#L137-L208
resource "azurerm_kubernetes_cluster_node_pool" "infracijenkinsio_agents_1_linux_x86_64_agents_1" {
  provider              = azurerm.jenkins-sponsored
  name                  = "lx86agt1"
  vm_size               = "Standard_D8ads_v7" # https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dasv7-series?tabs=sizebasic 8vcpu 	32Go
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 430 # Expecting an ephemeral OS disk. Specified size must be less than the instance local storage size. Ref. https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dadsv7-series?tabs=sizestoragelocal
  priority              = "Regular"
  orchestrator_version  = local.aks_clusters["infracijenkinsio_agents_1"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 20
  zones                 = local.aks_clusters.compute_zones_sponsored.amd64_pool
  vnet_subnet_id        = data.azurerm_subnet.infra_ci_jenkins_io_sponsored_kubernetes_agents.id

  upgrade_settings {
    max_surge = "10%"
  }

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
resource "azurerm_kubernetes_cluster_node_pool" "infracijenkinsio_agents_1_linux_arm64_agents_1" {
  provider              = azurerm.jenkins-sponsored
  name                  = "la64agt1"
  vm_size               = "Standard_D16pds_v6" # https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dpdsv6-series?tabs=sizebasic 	16vcpu 	64Go 440ssd
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 430       # Expecting an ephemeral OS disk. Specified size must be less than the instance local storage size. Ref. https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dpdsv6-series?tabs=sizestoragelocal
  priority              = "Regular" # No spot quota in Jenkins Subscription
  orchestrator_version  = local.aks_clusters["infracijenkinsio_agents_1"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 20
  zones                 = local.aks_clusters.compute_zones_sponsored.arm64_pool
  vnet_subnet_id        = data.azurerm_subnet.infra_ci_jenkins_io_sponsored_kubernetes_agents.id

  upgrade_settings {
    max_surge = "10%"
  }

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
resource "kubernetes_namespace" "infracijenkinsio_agents_1_infra_ci_jenkins_io_agents" {
  provider = kubernetes.infracijenkinsio_agents_1

  metadata {
    name = "jenkins-infra-agents"
    labels = {
      name = "jenkins-infra-agents"
    }
  }
}
resource "kubernetes_service_account" "infracijenkinsio_agents_1_infra_ci_jenkins_io_agents" {
  provider = kubernetes.infracijenkinsio_agents_1

  metadata {
    name      = "jenkins-infra-agent"
    namespace = kubernetes_namespace.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents.metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents_jenkins_sponsored.client_id
    }
  }
}
resource "azurerm_federated_identity_credential" "infracijenkinsio_agents_1_infra_ci_jenkins_io_agents" {
  provider                  = azurerm.jenkins-sponsored
  name                      = "infracijenkinsio-agents-1-${kubernetes_service_account.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents.metadata[0].name}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents_jenkins_sponsored.id
  subject                   = "system:serviceaccount:${kubernetes_namespace.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents.metadata[0].name}:${kubernetes_service_account.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents.metadata[0].name}"
}

#Configure the jenkins-infra/kubernetes-management admin service account
module "infracijenkinsio_agents_1_admin_sa" {
  providers = {
    kubernetes = kubernetes.infracijenkinsio_agents_1
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.name
  cluster_hostname           = local.aks_clusters_outputs.infracijenkinsio_agents_1.cluster_hostname
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.infracijenkinsio_agents_1.kube_config.0.cluster_ca_certificate
}
output "kubeconfig_management_infracijenkinsio_agents_1" {
  sensitive = true
  value     = module.infracijenkinsio_agents_1_admin_sa.kubeconfig
}
