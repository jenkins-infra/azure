###### TODO delete legacy resources above once migration to the new `publick8s` cluster is finished

# Important: the Enterprise Application "terraform-production" used by this repo pipeline needs to be able to manage this vnet
# See the corresponding role assignment for this cluster added here (private repo):
# https://github.com/jenkins-infra/terraform-states/blob/44521bf0a03b4ab1a99712c215d40afafcaf04d6/azure/main.tf#L75
data "azurerm_subnet" "publick8s_tier" {
  name                 = "publick8s-tier"
  resource_group_name  = data.azurerm_resource_group.public.name
  virtual_network_name = data.azurerm_virtual_network.public.name
}

data "azurerm_subnet" "public_vnet_data_tier" {
  name                 = "public-vnet-data-tier"
  resource_group_name  = data.azurerm_resource_group.public.name
  virtual_network_name = data.azurerm_virtual_network.public.name
}

resource "random_pet" "suffix_publick8s" {
  # You want to taint this resource in order to get a new pet
}

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "old_publick8s" {
  name                = local.aks_clusters["old_publick8s"].name
  location            = azurerm_resource_group.publick8s.location
  resource_group_name = azurerm_resource_group.publick8s.name
  kubernetes_version  = local.aks_clusters["old_publick8s"].kubernetes_version
  dns_prefix          = local.aks_clusters["old_publick8s"].name
  # default value but made explicit to please trivy
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  upgrade_override {
    # TODO: disable to avoid "surprise" upgrades
    force_upgrade_enabled = true
  }

  api_server_access_profile {
    authorized_ip_ranges = setunion(
      # admins
      formatlist(
        "%s/32",
        flatten(
          concat(
            # TODO: remove when publick8s will be changed to a "private" cluster
            [for key, value in local.admin_public_ips : value],
            # TODO: remove when publick8s will be changed to a "private" cluster
            local.outbound_ips_publick8s_jenkins_io,
            split(" ", local.outbound_ips_infra_ci_jenkins_io),
          )
        )
      ),
      # private VPN access
      data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
    )
  }

  image_cleaner_interval_hours = 48

  #trivy:ignore:azure-container-configured-network-policy
  network_profile {
    network_plugin = "kubenet"
    # These ranges must NOT overlap with any of the subnets
    pod_cidrs         = ["10.100.0.0/16", "fd12:3456:789a::/64"]
    ip_versions       = ["IPv4", "IPv6"]
    outbound_type     = "loadBalancer"
    load_balancer_sku = "standard"
    load_balancer_profile {
      outbound_ports_allocated    = "2560" # Max 25 Nodes, 64000 ports total per public IP
      idle_timeout_in_minutes     = "4"
      managed_outbound_ip_count   = "3"
      managed_outbound_ipv6_count = "2"
    }
  }

  default_node_pool {
    name                         = "systempool3"
    only_critical_addons_enabled = true               # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2as_v4" # 2 vCPU, 8 GB RAM, 16 GB disk, 4000 IOPS
    upgrade_settings {
      max_surge = "10%"
    }
    kubelet_disk_type    = "OS"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 50
    orchestrator_version = local.aks_clusters["old_publick8s"].kubernetes_version
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = 4
    vnet_subnet_id       = data.azurerm_subnet.publick8s_tier.id
    tags                 = local.default_tags
    zones                = local.aks_clusters["old_publick8s"].compute_zones
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

data "azurerm_kubernetes_cluster" "old_publick8s" {
  name                = local.aks_clusters["old_publick8s"].name
  resource_group_name = azurerm_resource_group.publick8s.name
}

resource "azurerm_kubernetes_cluster_node_pool" "arm64small2" {
  name    = "arm64small2"
  vm_size = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["old_publick8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.old_publick8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 10
  zones                 = [1]
  vnet_subnet_id        = data.azurerm_subnet.publick8s_tier.id

  node_taints = [
    "kubernetes.io/arch=arm64:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Allow cluster to manage LBs in the publick8s-tier subnet (Public LB)
resource "azurerm_role_assignment" "old_publick8s_public_vnet_networkcontributor" {
  scope                            = data.azurerm_virtual_network.public.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
data "azurerm_nat_gateway" "publick8s_outbound" {
  resource_group_name = data.azurerm_virtual_network.public.resource_group_name
  name                = "publick8s-outbound"
}
resource "azurerm_role_definition" "old_publick8s_outbound_gateway" {
  name  = "publick8s_outbount_gateway"
  scope = data.azurerm_nat_gateway.publick8s_outbound.id

  permissions {
    actions = ["Microsoft.Network/natGateways/join/action"]
  }
}

resource "azurerm_role_assignment" "old_publick8s_nat_gateway" {
  scope                            = data.azurerm_nat_gateway.publick8s_outbound.id
  role_definition_id               = azurerm_role_definition.old_publick8s_outbound_gateway.role_definition_resource_id
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage publick8s_ipv4
resource "azurerm_role_assignment" "old_publick8s_ipv4_networkcontributor" {
  scope                            = azurerm_public_ip.old_publick8s_ipv4.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage ldap_jenkins_io_ipv4
resource "azurerm_role_assignment" "old_ldap_jenkins_io_ipv4_networkcontributor" {
  scope                            = azurerm_public_ip.old_ldap_jenkins_io_ipv4.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage publick8s_ipv6
resource "azurerm_role_assignment" "old_publick8s_ipv6_networkcontributor" {
  scope                            = azurerm_public_ip.old_publick8s_ipv6.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "old_public_ips_networkcontributor" {
  scope                            = azurerm_resource_group.prod_public_ips.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
resource "kubernetes_storage_class" "managed_csi_premium_retain_public" {
  metadata {
    name = "managed-csi-premium-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
  provider               = kubernetes.oldpublick8s
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "managed_csi_premium_ZRS_retain_public" {
  metadata {
    name = "managed-csi-premium-zrs-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_ZRS"
  }
  provider               = kubernetes.oldpublick8s
  allow_volume_expansion = true
}

# https://learn.microsoft.com/en-us/java/api/com.microsoft.azure.management.storage.skuname?view=azure-java-legacy#field-summary
resource "kubernetes_storage_class" "managed_csi_standard_ZRS_retain_public" {
  metadata {
    name = "managed-csi-standard-zrs-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = " Standard_ZRS"
  }
  provider               = kubernetes.oldpublick8s
  allow_volume_expansion = true
}

# TODO: remove this class once all PV/PVCs have been patched
resource "kubernetes_storage_class" "statically_provisionned_publick8s" {
  metadata {
    name = "statically-provisionned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  provider               = kubernetes.oldpublick8s
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "statically_provisioned_publick8s" {
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  provider               = kubernetes.oldpublick8s
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "azurefile_csi_premium_retain_public" {
  metadata {
    name = "azurefile-csi-premium-retain"
  }
  storage_provisioner = "file.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
  mount_options = ["dir_mode=0777", "file_mode=0777", "uid=1000", "gid=1000", "mfsymlinks", "nobrl"]
  provider      = kubernetes.oldpublick8s
}

# Used later by the load balancer deployed on the cluster, see https://github.com/jenkins-infra/kubernetes-management/config/publick8s.yaml

resource "azurerm_public_ip" "old_publick8s_ipv4" {
  name                = "public-publick8s-ipv4"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv4"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}

resource "azurerm_management_lock" "old_publick8s_ipv4" {
  name       = "public-publick8s-ipv4"
  scope      = azurerm_public_ip.old_publick8s_ipv4.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}

# The LDAP service deployed on this cluster is using TCP not HTTP/HTTPS, it needs its own load balancer
# Setting it with this determined public IP will ease DNS setup and changes

resource "azurerm_public_ip" "old_ldap_jenkins_io_ipv4" {
  name                = "ldap-jenkins-io-ipv4"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv4"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "old_ldap_jenkins_io_ipv4" {
  name       = "ldap-jenkins-io-ipv4"
  scope      = azurerm_public_ip.old_ldap_jenkins_io_ipv4.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}

resource "azurerm_public_ip" "old_publick8s_ipv6" {
  name                = "public-publick8s-ipv6"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv6"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}

resource "azurerm_management_lock" "old_publick8s_ipv6" {
  name       = "public-publick8s-ipv6"
  scope      = azurerm_public_ip.old_publick8s_ipv6.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}
# Configure the jenkins-infra/kubernetes-management admin service account
module "old_publick8s_admin_sa" {
  providers = {
    kubernetes = kubernetes.oldpublick8s
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.old_publick8s.name
  cluster_hostname           = azurerm_kubernetes_cluster.old_publick8s.kube_config.0.host
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.old_publick8s.kube_config.0.cluster_ca_certificate
}

# Retrieve effective outbound IPs
data "azurerm_public_ip" "publick8s_lb_outbound" {
  ## Disable this resource when running in terratest
  # to avoid the error "The "for_each" set includes values derived from resource attributes that cannot be determined until apply"
  for_each = var.terratest ? toset([]) : toset(concat(flatten(azurerm_kubernetes_cluster.old_publick8s.network_profile[*].load_balancer_profile[*].effective_outbound_ips)))

  name                = element(split("/", each.key), "-1")
  resource_group_name = azurerm_kubernetes_cluster.old_publick8s.node_resource_group
}

resource "kubernetes_namespace" "oldpublick8s_builds_reports_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = azurerm_storage_share.builds_reports_jenkins_io.name
    labels = {
      name = azurerm_storage_share.builds_reports_jenkins_io.name
    }
  }
}
resource "kubernetes_namespace" "oldpublick8s_data_storage_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "data-storage-jenkins-io"
  }
}
resource "kubernetes_namespace" "oldpublick8s_get_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "get-jenkins-io"
  }
}
resource "kubernetes_namespace" "oldpublick8s_javadoc_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "javadoc-jenkins-io"
  }
}
resource "kubernetes_namespace" "oldpublick8s_ldap" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "ldap"
    labels = {
      name = "ldap"
    }
  }
}
resource "kubernetes_namespace" "oldpublick8s_updates_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "updates-jenkins-io"
  }
}
resource "kubernetes_namespace" "oldpublick8s_www_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name = "www-jenkins-io"
  }
}
resource "kubernetes_secret" "oldpublick8s_builds_reports_jenkins_io" {
  provider = kubernetes.oldpublick8s

  metadata {
    name      = azurerm_storage_share.builds_reports_jenkins_io.name
    namespace = azurerm_storage_share.builds_reports_jenkins_io.name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.builds_reports_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.builds_reports_jenkins_io.primary_access_key
  }

  type = "Opaque"
}
resource "kubernetes_secret" "oldpublick8s_data_storage_jenkins_io_storage_account" {
  provider = kubernetes.oldpublick8s

  metadata {
    name      = "data-storage-jenkins-io-storage-account"
    namespace = kubernetes_namespace.oldpublick8s_data_storage_jenkins_io.metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.data_storage_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.data_storage_jenkins_io.primary_access_key
  }

  type = "Opaque"
}
resource "kubernetes_secret" "oldpublick8s_ldap_jenkins_io_backup" {
  provider = kubernetes.oldpublick8s

  metadata {
    name      = "ldap-backup-storage"
    namespace = kubernetes_namespace.oldpublick8s_ldap.metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.ldap_backups.name
    azurestorageaccountkey  = azurerm_storage_account.ldap_backups.primary_access_key
  }

  type = "Opaque"
}
resource "kubernetes_persistent_volume" "builds_reports_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = azurerm_storage_share.builds_reports_jenkins_io.name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.builds_reports_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {                                                                                # To ensure no other PVCs can claim this PV
      namespace = kubernetes_namespace.oldpublick8s_builds_reports_jenkins_io.metadata[0].name # Namespace is required even though it's in "default" namespace.
      name      = azurerm_storage_share.builds_reports_jenkins_io.name                         # Name of your PVC (cannot be a direct reference to avoid cyclical errors)
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
        volume_handle = format("%s-%s", azurerm_storage_account.builds_reports_jenkins_io.name, azurerm_storage_share.builds_reports_jenkins_io.name)
        read_only     = true
        volume_attributes = {
          resourceGroup = azurerm_storage_account.builds_reports_jenkins_io.resource_group_name
          shareName     = azurerm_storage_share.builds_reports_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.oldpublick8s_builds_reports_jenkins_io.metadata[0].name
          namespace = kubernetes_secret.oldpublick8s_builds_reports_jenkins_io.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "builds_reports_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = kubernetes_persistent_volume.builds_reports_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.oldpublick8s_builds_reports_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.builds_reports_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.builds_reports_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.builds_reports_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.builds_reports_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}

resource "kubernetes_persistent_volume" "get_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = kubernetes_namespace.oldpublick8s_get_jenkins_io.metadata[0].name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
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
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = kubernetes_namespace.oldpublick8s_get_jenkins_io.metadata[0].name
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName      = azurerm_storage_share.data_storage_jenkins_io.name
          storageAccount = azurerm_storage_account.data_storage_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "get_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = kubernetes_persistent_volume.get_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.oldpublick8s_get_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.get_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.get_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.get_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.get_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}
resource "kubernetes_persistent_volume" "javadoc_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = kubernetes_namespace.oldpublick8s_javadoc_jenkins_io.metadata[0].name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
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
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = kubernetes_namespace.oldpublick8s_javadoc_jenkins_io.metadata[0].name
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName      = azurerm_storage_share.data_storage_jenkins_io.name
          storageAccount = azurerm_storage_account.data_storage_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "javadoc_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = kubernetes_persistent_volume.javadoc_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.oldpublick8s_javadoc_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.javadoc_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.javadoc_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.javadoc_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.javadoc_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}
resource "kubernetes_persistent_volume" "ldap_jenkins_io_data" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = "ldap-jenkins-io-pv"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.ldap_jenkins_io_data_old.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisionned_publick8s.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.ldap_jenkins_io_data_old.id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "ldap_jenkins_io_data" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = "ldap-jenkins-io-data"
    namespace = "ldap"
  }
  spec {
    access_modes       = kubernetes_persistent_volume.ldap_jenkins_io_data.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.ldap_jenkins_io_data.metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned_publick8s.id
    resources {
      requests = {
        storage = "${azurerm_managed_disk.ldap_jenkins_io_data_old.disk_size_gb}Gi"
      }
    }
  }
}

# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "ldap_jenkins_io_controller_disk_reader" {
  name  = "ReadLDAPDisk"
  scope = azurerm_resource_group.ldap.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "ldap_jenkins_io_allow_azurerm" {
  scope              = azurerm_resource_group.ldap.id
  role_definition_id = azurerm_role_definition.ldap_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
}
# Persistent Data available in read and write
resource "kubernetes_persistent_volume" "ldap_jenkins_io_backup" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = "ldap-jenkins-io-backup"
  }
  spec {
    capacity = {
      # between 3 to 8 years of LDAP ldip backups
      # TODO: We should purge backups older than 1 year (username, email and password data)
      storage = "10Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
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
        volume_handle = "${azurerm_storage_share.ldap.name}-rwx"
        read_only     = false
        volume_attributes = {
          resourceGroup = azurerm_storage_account.ldap_backups.resource_group_name
          shareName     = azurerm_storage_share.ldap.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.oldpublick8s_ldap_jenkins_io_backup.metadata[0].name
          namespace = kubernetes_secret.oldpublick8s_ldap_jenkins_io_backup.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "ldap_jenkins_io_backup" {
  provider = kubernetes.oldpublick8s

  metadata {
    name      = kubernetes_persistent_volume.ldap_jenkins_io_backup.metadata[0].name
    namespace = kubernetes_namespace.oldpublick8s_ldap.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.ldap_jenkins_io_backup.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.ldap_jenkins_io_backup.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.ldap_jenkins_io_backup.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.ldap_jenkins_io_backup.spec[0].capacity.storage
      }
    }
  }
}
resource "kubernetes_persistent_volume" "updates_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = kubernetes_namespace.oldpublick8s_updates_jenkins_io.metadata[0].name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
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
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = kubernetes_namespace.oldpublick8s_updates_jenkins_io.metadata[0].name
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName      = azurerm_storage_share.data_storage_jenkins_io.name
          storageAccount = azurerm_storage_account.data_storage_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "updates_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = kubernetes_persistent_volume.updates_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.oldpublick8s_updates_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.updates_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.updates_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.updates_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.updates_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}

resource "kubernetes_persistent_volume" "jenkins_weekly_data" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = "jenkins-weekly-pv"
  }
  spec {
    capacity = {
      storage = "${azurerm_managed_disk.jenkins_weekly_data.disk_size_gb}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisionned_publick8s.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = azurerm_managed_disk.jenkins_weekly_data.id
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "jenkins_weekly_data" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = "jenkins-weekly-data"
    namespace = "jenkins-weekly"
  }
  spec {
    access_modes       = kubernetes_persistent_volume.jenkins_weekly_data.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.jenkins_weekly_data.metadata.0.name
    storage_class_name = kubernetes_storage_class.statically_provisionned_publick8s.id
    resources {
      requests = {
        storage = "${azurerm_managed_disk.jenkins_weekly_data.disk_size_gb}Gi"
      }
    }
  }
}

# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "weekly_ci_jenkins_io_controller_disk_reader" {
  name  = "ReadWeeklyCIDisk"
  scope = azurerm_resource_group.weekly_ci_controller.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "weekly_ci_jenkins_io_allow_azurerm" {
  scope              = azurerm_resource_group.weekly_ci_controller.id
  role_definition_id = azurerm_role_definition.weekly_ci_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
}

resource "kubernetes_persistent_volume" "www_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name = kubernetes_namespace.oldpublick8s_www_jenkins_io.metadata[0].name
  }
  spec {
    capacity = {
      storage = "${azurerm_storage_share.data_storage_jenkins_io.quota}Gi"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.statically_provisioned_publick8s.id
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
        # `volumeHandle` must be unique on the cluster for this volume
        volume_handle = kubernetes_namespace.oldpublick8s_www_jenkins_io.metadata[0].name
        read_only     = false
        volume_attributes = {
          protocol       = "nfs"
          resourceGroup  = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName      = azurerm_storage_share.data_storage_jenkins_io.name
          storageAccount = azurerm_storage_account.data_storage_jenkins_io.name
        }
        node_stage_secret_ref {
          name      = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].name
          namespace = kubernetes_secret.oldpublick8s_data_storage_jenkins_io_storage_account.metadata[0].namespace
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "www_jenkins_io" {
  provider = kubernetes.oldpublick8s
  metadata {
    name      = kubernetes_persistent_volume.www_jenkins_io.metadata[0].name
    namespace = kubernetes_namespace.oldpublick8s_www_jenkins_io.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.www_jenkins_io.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.www_jenkins_io.metadata[0].name
    storage_class_name = kubernetes_persistent_volume.www_jenkins_io.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.www_jenkins_io.spec[0].capacity.storage
      }
    }
  }
}

#### TODO: remove old resources below
resource "azurerm_resource_group" "weekly_ci_controller" {
  name     = "weekly-ci"
  location = var.location
}

resource "azurerm_managed_disk" "jenkins_weekly_data" {
  name                 = "jenkins-weekly-data"
  location             = azurerm_resource_group.weekly_ci_controller.location
  resource_group_name  = azurerm_resource_group.weekly_ci_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 8
  tags                 = local.default_tags
}
