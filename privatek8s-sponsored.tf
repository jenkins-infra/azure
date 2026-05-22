########################################################################################################
# Resources in other Resource Groups ("RG") in the CDF subscription
# which lifecycle are not bound directly to the cluster and its RG.
########################################################################################################
# Used later by the load balancer deployed on the cluster
# Use case is to allow incoming webhooks
resource "azurerm_public_ip" "privatek8s_sponsored_public" {
  provider = azurerm.jenkins-sponsored

  name                = "privatek8s-sponsored-public"
  resource_group_name = azurerm_resource_group.prod_public_ips_sponsored.name
  location            = azurerm_resource_group.prod_public_ips_sponsored.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "privatek8s_sponsored_public" {
  provider = azurerm.jenkins-sponsored

  name       = "privatek8s-sponsored-public"
  scope      = azurerm_public_ip.privatek8s_sponsored_public.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when privatek8s-sponsored is removed"
}
resource "azurerm_dns_a_record" "privatek8s_sponsored_public" {
  # same provider as the DNS zone
  name                = "public.privatek8s-sponsored"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.privatek8s_sponsored_public.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "privatek8s_sponsored_private" {
  # same provider as the DNS zone
  name                = "private.privatek8s-sponsored"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records = [
    # Let's specify an IP at the end of the range to have low probability of being used
    cidrhost(
      data.azurerm_subnet.privatek8s_sponsored_commons.address_prefixes[0],
      -2,
    )
  ]
  tags = local.default_tags
}

########################################################################################################
# AzureRM resources related to the cluster in the sponsored subscription
########################################################################################################
resource "azurerm_resource_group" "privatek8s_sponsored" {
  provider = azurerm.jenkins-sponsored
  name     = "privatek8s-aks-sponsored"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_kubernetes_cluster" "privatek8s_sponsored" {
  provider = azurerm.jenkins-sponsored
  name     = local.aks_clusters["privatek8s-sponsored"].name
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = replace(local.aks_clusters["privatek8s-sponsored"].name, "-", "") # Avoid hyphens in this DNS host
  location                            = azurerm_resource_group.privatek8s_sponsored.location
  resource_group_name                 = azurerm_resource_group.privatek8s_sponsored.name
  kubernetes_version                  = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
  role_based_access_control_enabled   = true
  oidc_issuer_enabled                 = true
  workload_identity_enabled           = true
  automatic_upgrade_channel           = "node-image"
  node_os_upgrade_channel             = "NodeImage"

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard" # Required to customize the outbound type
    pod_cidr            = local.aks_clusters["privatek8s-sponsored"].pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "syspool"
    only_critical_addons_enabled = true                # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2ads_v7" # At least 2 vCPUS as per AKS best practises

    temporary_name_for_rotation = "syspooltemp"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "AzureLinux"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 110 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv7-series?tabs=sizestoragelocal (depends on the instance size)
    orchestrator_version = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = 3
    vnet_subnet_id       = data.azurerm_subnet.privatek8s_sponsored_app.id
    tags                 = local.default_tags
    zones                = [2] # Only one zone available - ref. https://github.com/jenkins-infra/azure/pull/1460/changes#r3281970045
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_sponsored_linuxpool" {
  provider = azurerm.jenkins-sponsored
  name     = "linuxpool" # 12 char. max on Linux, only letters and numbers
  vm_size  = "Standard_D4ads_v7"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 220 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv7-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsored.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [2] # https://github.com/jenkins-infra/azure/pull/1458/changes#r3282193453
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsored_app.id

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_sponsored_infra_ci_jenkins_io_controller" {
  provider = azurerm.jenkins-sponsored
  name     = "infracictrl" # 12 char. max on Linux, only letters and numbers
  vm_size  = "Standard_D4pds_v6"
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 220 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dpdsv6-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsored.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 2
  zones                 = [1, 2] # https://github.com/jenkins-infra/azure/pull/1458/changes#r3282196193
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsored_infra_ci_jenkins_io_controller.id

  node_taints = [
    "jenkins=infra.ci.jenkins.io:NoSchedule",
    "jenkins-component=controller:NoSchedule"
  ]
  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_sponsored_release_ci_jenkins_io_controller" {
  provider = azurerm.jenkins-sponsored
  name     = "releacictrl" # 12 char. max on Linux, only letters and numbers
  vm_size  = "Standard_D4pds_v6"
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 220 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dpdsv6-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsored.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 2
  zones                 = [1, 2] # https://github.com/jenkins-infra/azure/pull/1458/changes#r3282199055
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsored_release_ci_jenkins_io_controller.id

  node_taints = [
    "jenkins=release.ci.jenkins.io:NoSchedule",
    "jenkins-component=controller:NoSchedule"
  ]
  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_sponsored_release_ci_jenkins_io_agents_linux" {
  provider = azurerm.jenkins-sponsored
  name     = "releacilinux" # 12 char. max on Linux, only letters and numbers
  vm_size  = "Standard_D8ads_v7"
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 440 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv7-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsored.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [2] # https://github.com/jenkins-infra/azure/pull/1458/changes#r3282201958
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsored_release_ci_jenkins_io_agents.id
  node_taints = [
    "jenkins=release.ci.jenkins.io:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_sponsored_release_ci_jenkins_io_agents_windows_2022" {
  provider = azurerm.jenkins-sponsored
  name     = "w2022" # 6 char. max on Windows, only letters and numbers
  #####
  # Note: we must stay on Generation 1 VMs (_v5 families max.) because Generation 2 requires Windows 2025.
  # Despite MS documentation: https://learn.microsoft.com/en-us/azure/aks/generation-2-vms?tabs=windows-node-pool#create-a-node-pool-with-a-gen-2-vm
  # the Terraform azurerm provider does not allow the custom "header" technique: https://github.com/hashicorp/terraform-provider-azurerm/issues/31526
  # And of course Windows 2025 is not available until https://github.com/hashicorp/terraform-provider-azurerm/issues/31036 is done.
  #
  # Last solution stop using Windows Node Pool in favor of Azure VM agents.
  #####
  vm_size = "Standard_D8s_v3" # Generation 1 VM
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 64 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dsv3-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsored.id
  os_type               = "Windows"
  os_sku                = "Windows2022"
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [1]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsored_release_ci_jenkins_io_agents.id
  node_taints = [
    "os=windows:NoSchedule",
    "jenkins=release.ci.jenkins.io:NoSchedule",
    "version=windows2022:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Allow cluster to manage network resources in the privatek8s_tier subnet
# It is used for managing the LBs of the public and private ingress controllers
resource "azurerm_role_assignment" "privatek8s_sponsored_subnets_networkcontributor" {
  provider = azurerm.jenkins-sponsored
  for_each = toset([
    data.azurerm_subnet.privatek8s_sponsored_app.id,
    data.azurerm_subnet.privatek8s_sponsored_infra_ci_jenkins_io_controller.id,
    data.azurerm_subnet.privatek8s_sponsored_release_ci_jenkins_io_agents.id,
    data.azurerm_subnet.privatek8s_sponsored_release_ci_jenkins_io_controller.id,
    data.azurerm_subnet.privatek8s_sponsored_commons.id,
  ])
  scope                            = each.key
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsored.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage the public IP privatek8s-sponsored
# It is used for managing the public IP of the LB of the public ingress controller
resource "azurerm_role_assignment" "privatek8s_sponsored_publicip_sponsored_networkcontributor" {
  provider                         = azurerm.jenkins-sponsored
  scope                            = azurerm_public_ip.privatek8s_sponsored_public.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsored.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow access to the private Azure Container Registry through an Azure Endpoint NIC
module "privatek8s_sponsored_acr_pe" {
  source = "./modules/azure-container-registry-private-links"

  providers = {
    azurerm     = azurerm.jenkins-sponsored
    azurerm.acr = azurerm
  }

  name = "privatek8ssponsored"

  acr_name     = azurerm_container_registry.dockerhub_mirror.name
  acr_location = azurerm_container_registry.dockerhub_mirror.location
  acr_rg_name  = azurerm_container_registry.dockerhub_mirror.resource_group_name

  subnet_name  = data.azurerm_subnet.privatek8s_sponsored_commons.name
  vnet_name    = data.azurerm_virtual_network.privatek8s_sponsored.name
  vnet_rg_name = data.azurerm_virtual_network.privatek8s_sponsored.resource_group_name

  default_tags = local.default_tags
}

###################################################################################
# Ressources from the Kubernetes provider
###################################################################################
resource "kubernetes_storage_class" "privatek8s_sponsored_statically_provisioned" {
  provider = kubernetes.privatek8s-sponsored
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
}

resource "kubernetes_namespace" "privatek8s_sponsored" {
  for_each = toset(["release-ci-jenkins-io", "infra-ci-jenkins-io", "release-ci-jenkins-io-agents", "data-storage-jenkins-io"])
  provider = kubernetes.privatek8s-sponsored
  metadata {
    name = each.key
    labels = {
      name = each.key
    }
  }
}

resource "kubernetes_secret" "privatek8s_sponsored_data_storage_jenkins_io_storage_account" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "data-storage-jenkins-io-storage-account"
    namespace = kubernetes_namespace.privatek8s_sponsored["data-storage-jenkins-io"].metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.data_storage_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.data_storage_jenkins_io.primary_access_key
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume" "privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage" {
  provider = kubernetes.privatek8s-sponsored
  metadata {
    name = "release-ci-jenkins-io-agents-data-storage"
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_sponsored_statically_provisioned.id
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {
      # NS of the PVC
      namespace = kubernetes_namespace.privatek8s_sponsored["release-ci-jenkins-io-agents"].metadata[0].name
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
          name      = kubernetes_secret.privatek8s_sponsored_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.privatek8s_sponsored_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage" {
  provider = kubernetes.privatek8s-sponsored
  metadata {
    name      = "data-storage-jenkins-io"
    namespace = kubernetes_namespace.privatek8s_sponsored["release-ci-jenkins-io-agents"].metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage.spec[0].capacity.storage
      }
    }
  }
}

resource "kubernetes_persistent_volume" "privatek8s_sponsored_infra_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name = "infra-ci-jenkins-io-data"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.infra_ci_jenkins_io_data_sponsored.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_sponsored_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.infra_ci_jenkins_io_data_sponsored.id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_sponsored_infra_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "infra-ci-jenkins-io-data"
    namespace = kubernetes_namespace.privatek8s_sponsored["infra-ci-jenkins-io"].metadata.0.name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data.spec.0.access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data.spec.0.storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data.spec.0.capacity.storage
      }
    }
  }
}
resource "kubernetes_persistent_volume" "privatek8s_sponsored_release_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name = "release-ci-jenkins-io-data"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.release_ci_jenkins_io_data_sponsored.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.privatek8s_sponsored_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.release_ci_jenkins_io_data_sponsored.id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "privatek8s_sponsored_release_ci_jenkins_io_data" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "release-ci-jenkins-io-data"
    namespace = kubernetes_namespace.privatek8s_sponsored["release-ci-jenkins-io"].metadata.0.name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data.spec.0.access_modes
    volume_name        = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data.spec.0.storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data.spec.0.capacity.storage
      }
    }
  }
}

###################################################################################
## Workload Identity Resources
###################################################################################
resource "kubernetes_service_account" "privatek8s_sponsored_infra_ci_jenkins_io_controller" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "infra-ci-jenkins-io-controller"
    namespace = kubernetes_namespace.privatek8s_sponsored["infra-ci-jenkins-io"].metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller_sponsored.client_id,
    }
  }
}
resource "azurerm_federated_identity_credential" "privatek8s_sponsored_infra_ci_jenkins_io_controller" {
  provider = azurerm.jenkins-sponsored

  name                      = "privatek8s-${kubernetes_service_account.privatek8s_sponsored_infra_ci_jenkins_io_controller.metadata[0].name}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.privatek8s_sponsored.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller_sponsored.id
  subject                   = "system:serviceaccount:${kubernetes_namespace.privatek8s_sponsored["infra-ci-jenkins-io"].metadata[0].name}:${kubernetes_service_account.privatek8s_sponsored_infra_ci_jenkins_io_controller.metadata[0].name}"
}
resource "kubernetes_service_account" "privatek8s_sponsored_release_ci_jenkins_io_controller" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "release-ci-jenkins-io-controller"
    namespace = kubernetes_namespace.privatek8s_sponsored["release-ci-jenkins-io"].metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.release_ci_jenkins_io_controller_sponsored.client_id,
    }
  }
}
resource "kubernetes_service_account" "privatek8s_sponsored_release_ci_jenkins_io_agents" {
  provider = kubernetes.privatek8s-sponsored

  metadata {
    name      = "release-ci-jenkins-io-agents"
    namespace = kubernetes_namespace.privatek8s_sponsored["release-ci-jenkins-io-agents"].metadata[0].name

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.release_ci_jenkins_io_agents_sponsored.client_id,
    }
  }
}
resource "azurerm_federated_identity_credential" "privatek8s_sponsored_release_ci_jenkins_io_agents" {
  provider = azurerm.jenkins-sponsored

  name                      = "privatek8s-${kubernetes_service_account.privatek8s_sponsored_release_ci_jenkins_io_agents.metadata[0].name}"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.privatek8s_sponsored.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.release_ci_jenkins_io_agents_sponsored.id
  subject                   = "system:serviceaccount:${kubernetes_namespace.privatek8s_sponsored["release-ci-jenkins-io-agents"].metadata[0].name}:${kubernetes_service_account.privatek8s_sponsored_release_ci_jenkins_io_agents.metadata[0].name}"
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "privatek8s_sponsored_admin_sa" {
  providers = {
    kubernetes = kubernetes.privatek8s-sponsored
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.privatek8s_sponsored.name
  cluster_hostname           = local.aks_clusters_outputs["privatek8s-sponsored"].cluster_hostname
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.privatek8s_sponsored.kube_config.0.cluster_ca_certificate
}
output "privatek8s_sponsoredadmin_sa_kubeconfig" {
  sensitive = true
  value     = module.privatek8s_sponsored_admin_sa.kubeconfig
}
