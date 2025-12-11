resource "azurerm_resource_group" "privatek8s" {
  name     = "privatek8s"
  location = var.location
  tags     = local.default_tags
}

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "privatek8s" {
  name     = local.aks_clusters["privatek8s"].name
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = local.aks_clusters["privatek8s"].name
  location                            = azurerm_resource_group.privatek8s.location
  resource_group_name                 = azurerm_resource_group.privatek8s.name
  kubernetes_version                  = local.aks_clusters["privatek8s"].kubernetes_version
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
    pod_cidr            = local.aks_clusters["privatek8s"].pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "syspool"
    only_critical_addons_enabled = true                # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2ads_v5" # At least 2 vCPUS as per AKS best practises

    temporary_name_for_rotation = "syspooltemp"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "AzureLinux"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 75 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv5-series?tabs=sizestoragelocal (depends on the instance size)
    orchestrator_version = local.aks_clusters["privatek8s"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.privatek8s_tier.id
    tags                 = local.default_tags
    zones                = [1, 2] # Many zones to ensure it is always able to provide machines in the region. Note: Zone 3 is not allowed for system pool.
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_linuxpool" {
  name    = "linuxpool"
  vm_size = "Standard_D4ads_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv5-series?tabs=sizestoragelocal (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [1, 2]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_tier.id

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# nodepool dedicated for the infra.ci.jenkins.io controller
resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_infracictrl" {
  name    = "infracictrl"
  vm_size = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 2
  zones                 = [2, 3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_infra_ci_controller_tier.id

  node_taints = [
    "jenkins=infra.ci.jenkins.io:NoSchedule",
    "jenkins-component=controller:NoSchedule"
  ]
  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# nodepool dedicated for the release.ci.jenkins.io controller
resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_releacictrl" {
  name    = "releacictrl"
  vm_size = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 2
  zones                 = [2, 3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_release_ci_controller_tier.id

  node_taints = [
    "jenkins=release.ci.jenkins.io:NoSchedule",
    "jenkins-component=controller:NoSchedule"
  ]
  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}
resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_releasepool" {

  name    = "releasepool"
  vm_size = "Standard_D8ads_v5" # 8 vCPU 32 GiB RAM
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 300 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [1, 2]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_release_tier.id
  node_taints = [
    "jenkins=release.ci.jenkins.io:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_releasepool_w2019" {

  # TODO: switch to w2022
  name    = "w2019"
  vm_size = "Standard_D4ads_v5" # 4 vCPU 16 GiB RAM
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type         = "Ephemeral"
  os_disk_size_gb      = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version = local.aks_clusters["privatek8s"].kubernetes_version
  os_type              = "Windows"
  # TODO: switch to w2022
  os_sku                = "Windows2019"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [1, 2]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_release_tier.id
  node_taints = [
    "os=windows:NoSchedule",
    "jenkins=release.ci.jenkins.io:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_releasepool_w2025" {
  name    = "w2025"
  vm_size = "Standard_D4ads_v5" # 4 vCPU 16 GiB RAM
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type         = "Ephemeral"
  os_disk_size_gb      = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version = local.aks_clusters["privatek8s"].kubernetes_version
  os_type              = "Windows"
  # TODO: switch to w2022
  os_sku                = "Windows2025"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [1, 2]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_release_tier.id
  node_taints = [
    "os=windows:NoSchedule",
    "jenkins=release.ci.jenkins.io:NoSchedule",
    "version=windows2025:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Allow cluster to manage network resources in the privatek8s_tier subnet
# It is used for managing the LBs of the public and private ingress controllers
resource "azurerm_role_assignment" "privatek8s_subnets_networkcontributor" {
  for_each = toset([
    data.azurerm_subnet.privatek8s_tier.id,
    data.azurerm_subnet.privatek8s_infra_ci_controller_tier.id,
    data.azurerm_subnet.privatek8s_release_ci_controller_tier.id,
    data.azurerm_subnet.privatek8s_release_tier.id,
  ])
  scope                            = each.key
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage the public IP privatek8s
# It is used for managing the public IP of the LB of the public ingress controller
resource "azurerm_role_assignment" "privatek8s_publicip_networkcontributor" {
  scope                            = azurerm_public_ip.privatek8s.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Used later by the load balancer deployed on the cluster
# Use case is to allow incoming webhooks
resource "azurerm_public_ip" "privatek8s" {
  name                = "public-privatek8s"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "privatek8s_publicip" {
  name       = "public-privatek8s-publicip"
  scope      = azurerm_public_ip.privatek8s.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when privatek8s is removed"
}

resource "azurerm_dns_a_record" "privatek8s_public" {
  name                = "public.privatek8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.privatek8s.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "privatek8s_private" {
  name                = "private.privatek8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records = [
    # Let's specify an IP at the end of the range to have low probability of being used
    cidrhost(
      data.azurerm_subnet.privatek8s_tier.address_prefixes[0],
      -2,
    )
  ]
  tags = local.default_tags
}


###################################################################################
# Ressources from the Kubernetes provider
###################################################################################
# Used by all the controller (for their Jenkins Home PVCs)
resource "kubernetes_storage_class" "privatek8s_statically_provisioned" {
  provider = kubernetes.privatek8s
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
}

# Persistent Volumes for infra.ci controller
resource "kubernetes_persistent_volume" "privatek8s_infra_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s

  metadata {
    name = "infra-ci-jenkins-io-data"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.infra_ci_jenkins_io_data.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.infra_ci_jenkins_io_data.id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_infra_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s

  metadata {
    name      = "infra-ci-jenkins-io-data"
    namespace = kubernetes_namespace.privatek8s["infra-ci-jenkins-io"].metadata.0.name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_infra_ci_jenkins_io_data.spec.0.access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_infra_ci_jenkins_io_data.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.privatek8s_infra_ci_jenkins_io_data.spec.0.storage_class_name
    resources {
      requests = {
        storage = "${azurerm_managed_disk.infra_ci_jenkins_io_data.disk_size_gb}Gi"
      }
    }
  }
}
# Persistent Volumes for release.ci controller
resource "kubernetes_persistent_volume" "privatek8s_release_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s

  metadata {
    name = "release-ci-jenkins-io-data"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.release_ci_jenkins_io_data.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.release_ci_jenkins_io_data.id
      }
    }
  }
}
resource "kubernetes_namespace" "privatek8s" {
  for_each = toset(["release-ci-jenkins-io", "infra-ci-jenkins-io", "release-ci-jenkins-io-agents", "data-storage-jenkins-io"])
  provider = kubernetes.privatek8s
  metadata {
    name = each.key
    labels = {
      name = each.key
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_release_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s

  metadata {
    name      = "release-ci-jenkins-io-data"
    namespace = kubernetes_namespace.privatek8s["release-ci-jenkins-io"].metadata.0.name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_data.spec.0.access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_data.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_data.spec.0.storage_class_name
    resources {
      requests = {
        storage = "${azurerm_managed_disk.release_ci_jenkins_io_data.disk_size_gb}Gi"
      }
    }
  }
}
resource "kubernetes_secret" "privatek8s_data_storage_jenkins_io_storage_account" {
  provider = kubernetes.privatek8s

  metadata {
    name      = "data-storage-jenkins-io-storage-account"
    namespace = kubernetes_namespace.privatek8s["data-storage-jenkins-io"].metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.data_storage_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.data_storage_jenkins_io.primary_access_key
  }

  type = "Opaque"
}

###################################################################################
## Workload Identity Resources
###################################################################################
# For infra.ci.jenkins.io controller
resource "kubernetes_service_account" "privatek8s_infra_ci_jenkins_io_controller" {
  provider = kubernetes.privatek8s

  metadata {
    name      = "infra-ci-jenkins-io-controller"
    namespace = kubernetes_namespace.privatek8s["infra-ci-jenkins-io"].metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller.client_id,
    }
  }
}
resource "azurerm_federated_identity_credential" "privatek8s_infra_ci_jenkins_io_controller" {
  name      = "privatek8s-${kubernetes_service_account.privatek8s_infra_ci_jenkins_io_controller.metadata[0].name}"
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.privatek8s.oidc_issuer_url
  parent_id = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller.id
  # RG must be the same for both the UAID and the federated ID (otherwise you get HTTP/404 during the "apply" phase)
  resource_group_name = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller.resource_group_name
  subject             = "system:serviceaccount:${kubernetes_namespace.privatek8s["infra-ci-jenkins-io"].metadata[0].name}:${kubernetes_service_account.privatek8s_infra_ci_jenkins_io_controller.metadata[0].name}"
}
## End of infra.ci

## For release.ci.jenkins.io
resource "kubernetes_service_account" "privatek8s_release_ci_jenkins_io_controller" {
  provider = kubernetes.privatek8s

  metadata {
    name      = "release-ci-jenkins-io-controller"
    namespace = kubernetes_namespace.privatek8s["release-ci-jenkins-io"].metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.release_ci_jenkins_io_controller.client_id,
    }
  }
}
resource "kubernetes_service_account" "privatek8s_release_ci_jenkins_io_agents" {
  provider = kubernetes.privatek8s

  metadata {
    name      = "release-ci-jenkins-io-agents"
    namespace = kubernetes_namespace.privatek8s["release-ci-jenkins-io-agents"].metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.release_ci_jenkins_io_agents.client_id,
    }
  }
}
resource "azurerm_federated_identity_credential" "privatek8s_release_ci_jenkins_io_agents" {
  name     = "privatek8s-${kubernetes_service_account.privatek8s_release_ci_jenkins_io_agents.metadata[0].name}"
  audience = ["api://AzureADTokenExchange"]
  issuer   = azurerm_kubernetes_cluster.privatek8s.oidc_issuer_url
  # RG must be the same for both the UAID and the federated ID (otherwise you get HTTP/404 during the "apply" phase)
  parent_id           = azurerm_user_assigned_identity.release_ci_jenkins_io_agents.id
  resource_group_name = azurerm_user_assigned_identity.release_ci_jenkins_io_agents.resource_group_name
  subject             = "system:serviceaccount:${kubernetes_namespace.privatek8s["release-ci-jenkins-io-agents"].metadata[0].name}:${kubernetes_service_account.privatek8s_release_ci_jenkins_io_agents.metadata[0].name}"
}
## End of release.ci.jenkins.io agents
### End of  Workload Identity Resources

# Configure the jenkins-infra/kubernetes-management admin service account
module "privatek8s_admin_sa" {
  providers = {
    kubernetes = kubernetes.privatek8s
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.privatek8s.name
  cluster_hostname           = local.aks_clusters_outputs.privatek8s.cluster_hostname
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.privatek8s.kube_config.0.cluster_ca_certificate
}
output "privatek8s_admin_sa_kubeconfig" {
  sensitive = true
  value     = module.privatek8s_admin_sa.kubeconfig
}

######## Persistent Volumes used by the "packaging" job in release.ci.jenkins.io
resource "kubernetes_persistent_volume" "privatek8s_release_ci_jenkins_io_agents_data_storage" {
  provider = kubernetes.privatek8s
  metadata {
    name = "release-ci-jenkins-io-agents-data-storage"
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_statically_provisioned.id
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {
      # NS of the PVC
      namespace = kubernetes_namespace.privatek8s["release-ci-jenkins-io-agents"].metadata[0].name
      name      = "data-storage-jenkins-io"
    }
    mount_options = [
      "nconnect=4", # Mandatory value (4) for Premium Azure File Share NFS 4.1. Increasing require using NetApp NFS instead ($$$)
      "noresvport", # ref. https://linux.die.net/man/5/nfs
      "actimeo=10", # Data is changed quite often
      "cto",        # Ensure data consistency at the cost of slower I/O
    ]
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
        volume_handle = "${azurerm_storage_account.data_storage_jenkins_io.resource_group_name}#${azurerm_storage_account.data_storage_jenkins_io.name}#${azurerm_storage_share.data_storage_jenkins_io.name}"
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName      = azurerm_storage_share.data_storage_jenkins_io.name
          storageAccount = azurerm_storage_account.data_storage_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.privatek8s_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.privatek8s_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_release_ci_jenkins_io_agents_data_storage" {
  provider = kubernetes.privatek8s
  metadata {
    name      = "data-storage-jenkins-io"
    namespace = kubernetes_namespace.privatek8s["release-ci-jenkins-io-agents"].metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.privatek8s_release_ci_jenkins_io_agents_data_storage.spec[0].capacity.storage
      }
    }
  }
}
