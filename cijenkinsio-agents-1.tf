resource "azurerm_resource_group" "cijenkinsio_kubernetes_agents" {
  provider = azurerm.jenkins-sponsorship
  name     = local.aks_clusters.cijenkinsio_agents_1.name
  location = var.location
  tags     = local.default_tags
}

#trivy:ignore:avd-azu-0040 # No need to enable oms_agent for Azure monitoring as we already have datadog
resource "azurerm_kubernetes_cluster" "cijenkinsio_agents_1" {
  provider = azurerm.jenkins-sponsorship
  name     = local.aks_clusters.cijenkinsio_agents_1.name
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - ci.jenkins.io controller to allow spawning agents (nominal usage)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  location                            = azurerm_resource_group.cijenkinsio_kubernetes_agents.location
  resource_group_name                 = azurerm_resource_group.cijenkinsio_kubernetes_agents.name
  kubernetes_version                  = local.aks_clusters.cijenkinsio_agents_1.kubernetes_version
  dns_prefix                          = replace(local.aks_clusters.cijenkinsio_agents_1.name, "-", "") # Avoid hyphens in this DNS host
  role_based_access_control_enabled   = true                                                           # default value but made explicit to please trivy

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard" # Required to customize the outbound type
    pod_cidr            = local.aks_clusters.cijenkinsio_agents_1.pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "syspool"
    only_critical_addons_enabled = true                # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2ads_v5" # At least 2 vCPUS as per AKS best practises
    temporary_name_for_rotation  = "syspooltemp"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "AzureLinux"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 75 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
    orchestrator_version = local.aks_clusters.cijenkinsio_agents_1.kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id
    tags                 = local.default_tags
    # Avoid deploying system pool in the same zone as other node pools
    zones = [for zone in local.aks_clusters.cijenkinsio_agents_1.compute_zones : zone + 1]
  }

  tags = local.default_tags
}

# Node pool to host "jenkins-infra" applications required on this cluster such as ACP or datadog's cluster-agent, e.g. "Not agent, neither AKS System tools"
resource "azurerm_kubernetes_cluster_node_pool" "linux_applications" {
  provider = azurerm.jenkins-sponsorship
  name     = "lx86n2app"
  vm_size  = "Standard_D4ads_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters.cijenkinsio_agents_1.kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 3 # 2 nodes always up for HA, a 3rd one is allowed for surge upgrades
  zones                 = local.aks_clusters.cijenkinsio_agents_1.compute_zones
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
resource "azurerm_kubernetes_cluster_node_pool" "linux_x86_64_n3_agents_1" {
  provider = azurerm.jenkins-sponsorship
  name     = "lx86n3agt1"
  vm_size  = "Standard_D16ads_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 600 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters.cijenkinsio_agents_1.kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 40 # 3 pods per nodes, max 120 pods - due to quotas
  zones                 = local.aks_clusters.cijenkinsio_agents_1.compute_zones
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
resource "azurerm_kubernetes_cluster_node_pool" "linux_x86_64_n3_bom_1" {
  provider = azurerm.jenkins-sponsorship
  name     = "lx86n3bom1"
  vm_size  = "Standard_D16ads_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 600 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters.cijenkinsio_agents_1.kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cijenkinsio_agents_1.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 50
  zones                 = local.aks_clusters.cijenkinsio_agents_1.compute_zones
  vnet_subnet_id        = data.azurerm_subnet.ci_jenkins_io_kubernetes_sponsorship.id

  node_labels = {
    "jenkins" = "ci.jenkins.io"
    "role"    = "jenkins-agents"
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

resource "kubernetes_storage_class" "statically_provisioned_cijenkinsio_agents_1" {
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner = "file.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
  provider               = kubernetes.cijenkinsio_agents_1
  allow_volume_expansion = true
}

# Allow AKS to manipulate LBs, PLS and join subnets - https://learn.microsoft.com/en-us/azure/aks/internal-lb?tabs=set-service-annotations#use-private-networks (see Note)
resource "azurerm_role_assignment" "cijio_agents_1_networkcontributor_vnet" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = data.azurerm_virtual_network.public_jenkins_sponsorship.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.cijenkinsio_agents_1.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "cijenkinsio_agents_1_admin_sa" {
  depends_on = [azurerm_kubernetes_cluster.cijenkinsio_agents_1]
  providers = {
    kubernetes = kubernetes.cijenkinsio_agents_1
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.cijenkinsio_agents_1.name
  cluster_hostname           = local.aks_clusters_outputs.cijenkinsio_agents_1.cluster_hostname
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.cluster_ca_certificate
}

# For infra.ci credentials
output "kubeconfig_management_cijenkinsio_agents_1" {
  sensitive = true
  value     = module.cijenkinsio_agents_1_admin_sa.kubeconfig
}

################################################################################################################################################################
## We define 3 PVCs (and associated PVs) all using the same Azure File Storage
## - 1 ReadWriteMany in a custom namespace which will be used to populate cache in a "non Jenkins agents namespace" (to avoid access through ci.jenkins.io)
## - 1 ReadOnlyMany per "Jenkins agents namespace" to allow consumption by container agents
################################################################################################################################################################
# Kubernetes Resources: PV and PVC must be statically provisioned
# Ref. https://github.com/awslabs/mountpoint-s3-csi-driver/tree/main?tab=readme-ov-file#features
resource "kubernetes_namespace" "ci_jenkins_io_jenkins_agents" {
  provider = kubernetes.cijenkinsio_agents_1

  for_each = local.aks_clusters.cijenkinsio_agents_1.agent_namespaces

  metadata {
    name = each.key
    labels = {
      name = "${each.key}"
    }
  }
}

resource "kubernetes_namespace" "ci_jenkins_io_maven_cache" {
  provider = kubernetes.cijenkinsio_agents_1

  metadata {
    name = "maven-cache"
    labels = {
      name = "maven-cache"
    }
  }
}
resource "kubernetes_secret" "ci_jenkins_io_maven_cache" {
  provider = kubernetes.cijenkinsio_agents_1

  metadata {
    name      = "ci-jenkins-io-maven-cache"
    namespace = kubernetes_namespace.ci_jenkins_io_maven_cache.metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.ci_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.ci_jenkins_io.primary_access_key
  }

  type = "Opaque"
}

### ReadOnly PVs consumed by Jenkins agents
resource "kubernetes_persistent_volume" "ci_jenkins_io_maven_cache_readonly" {
  provider = kubernetes.cijenkinsio_agents_1

  for_each = local.aks_clusters.cijenkinsio_agents_1.agent_namespaces

  metadata {
    name = format("%s-%s", azurerm_storage_share.ci_jenkins_io_maven_cache.name, lower(each.key))
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.ci_jenkins_io_maven_cache.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_cijenkinsio_agents_1.id
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {                                                        # To ensure no other PVCs can claim this PV
      namespace = each.key                                             # Namespace is required even though it's in "default" namespace.
      name      = azurerm_storage_share.ci_jenkins_io_maven_cache.name # Name of your PVC (cannot be a direct reference to avoid cyclical errors)
    }
    mount_options = [
      "dir_mode=0777",
      "file_mode=0777",
      "uid=0",
      "gid=0",
      "mfsymlinks",
      "cache=strict", # Default on usual kernels but worth setting it explicitly
      "nosharesock",  # Use new TCP connection for each CIFS mount (need more memory but avoid lost packets to create mount timeouts)
      "nobrl",        # disable sending byte range lock requests to the server and for applications which have challenges with posix locks
    ]
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = format("%s-%s", azurerm_storage_share.ci_jenkins_io_maven_cache.name, lower(each.key))
        read_only     = true
        volume_attributes = {
          resourceGroup = azurerm_storage_account.ci_jenkins_io.resource_group_name
          shareName     = azurerm_storage_share.ci_jenkins_io_maven_cache.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.ci_jenkins_io_maven_cache.metadata[0].name
          namespace = kubernetes_secret.ci_jenkins_io_maven_cache.metadata[0].namespace
        }
      }
    }
  }
}
### ReadOnly PVCs consumed by Jenkins agents
resource "kubernetes_persistent_volume_claim" "ci_jenkins_io_maven_cache_readonly" {
  provider = kubernetes.cijenkinsio_agents_1

  for_each = local.aks_clusters.cijenkinsio_agents_1.agent_namespaces

  metadata {
    name      = azurerm_storage_share.ci_jenkins_io_maven_cache.name
    namespace = each.key
  }
  spec {
    access_modes       = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].metadata.0.name
    storage_class_name = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].spec[0].capacity.storage
      }
    }
  }
}

### ReadWrite PV used to fill the cache
resource "kubernetes_persistent_volume" "ci_jenkins_io_maven_cache_write" {
  provider = kubernetes.cijenkinsio_agents_1

  metadata {
    name = format("%s-%s", azurerm_storage_share.ci_jenkins_io_maven_cache.name, kubernetes_namespace.ci_jenkins_io_maven_cache.metadata[0].name)
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.ci_jenkins_io_maven_cache.quota}Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "" # Required for static provisioning (even if empty)
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {                                                                   # To ensure no other PVCs can claim this PV
      namespace = kubernetes_namespace.ci_jenkins_io_maven_cache.metadata[0].name # Namespace is required even though it's in "default" namespace.
      name      = azurerm_storage_share.ci_jenkins_io_maven_cache.name            # Name of your PVC
    }
    mount_options = [
      "dir_mode=0777",
      "file_mode=0777",
      "uid=0",
      "gid=0",
      "mfsymlinks",
      "cache=strict", # Default on usual kernels but worth setting it explicitly
      "nosharesock",  # Use new TCP connection for each CIFS mount (need more memory but avoid lost packets to create mount timeouts)
      "nobrl",        # disable sending byte range lock requests to the server and for applications which have challenges with posix locks
    ]
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = format("%s-%s", azurerm_storage_share.ci_jenkins_io_maven_cache.name, kubernetes_namespace.ci_jenkins_io_maven_cache.metadata[0].name)
        read_only     = false
        volume_attributes = {
          resourceGroup = azurerm_storage_account.ci_jenkins_io.resource_group_name
          shareName     = azurerm_storage_share.ci_jenkins_io_maven_cache.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.ci_jenkins_io_maven_cache.metadata[0].name
          namespace = kubernetes_secret.ci_jenkins_io_maven_cache.metadata[0].namespace
        }
      }
    }
  }
}
### ReadWrite PVC used to fill the cache
resource "kubernetes_persistent_volume_claim" "ci_jenkins_io_maven_cache_write" {
  provider = kubernetes.cijenkinsio_agents_1

  metadata {
    name      = azurerm_storage_share.ci_jenkins_io_maven_cache.name
    namespace = kubernetes_namespace.ci_jenkins_io_maven_cache.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.spec[0].capacity.storage
      }
    }
  }
}
################################################################################################################################################################
