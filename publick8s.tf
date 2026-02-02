resource "azurerm_resource_group" "publick8s" {
  name     = "publick8s"
  location = var.location
  tags     = local.default_tags
}

data "azurerm_subnet" "publick8s" {
  name                 = "publick8s"
  resource_group_name  = data.azurerm_resource_group.public.name
  virtual_network_name = data.azurerm_virtual_network.public.name
}

resource "azurerm_dns_a_record" "public_publick8s" {
  name                = "public.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_public_ip.publick8s_ips["publick8s-public-ipv4"].ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_aaaa_record" "public_publick8s" {
  name                = "public.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_public_ip.publick8s_ips["publick8s-public-ipv6"].ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "private_publick8s" {
  name                = "private.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = ["10.245.2.12"] # External IP of the private-nginx ingress LoadBalancer, created by https://github.com/jenkins-infra/kubernetes-management/blob/54a0d4aa72b15f4236abcfbde00a080905bbb890/clusters/publick8s.yaml#L63-L69
  tags                = local.default_tags
}

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "publick8s" {
  name     = local.aks_clusters["publick8s"].name
  location = azurerm_resource_group.publick8s.location
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true

  resource_group_name = azurerm_resource_group.publick8s.name
  kubernetes_version  = local.aks_clusters["publick8s"].kubernetes_version
  dns_prefix          = local.aks_clusters["publick8s"].name

  # default value but made explicit to please trivy
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidrs           = local.aks_clusters["publick8s"].pod_cidrs # Plural form: dual stack ipv4/ipv6
    ip_versions         = ["IPv4", "IPv6"]
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
    load_balancer_profile {
      outbound_ports_allocated    = "2560" # Max 25 Nodes, 64000 ports total per public IP
      idle_timeout_in_minutes     = "4"
      managed_outbound_ip_count   = "3"
      managed_outbound_ipv6_count = "2"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "linuxpool"
    only_critical_addons_enabled = false               # We run our workloads along the system workloads
    vm_size                      = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
    upgrade_settings {
      drain_timeout_in_minutes = 5 # If a pod cannot be evicted in less than 5 min, then upgrades fails
      max_surge                = 1 # Upgrade node one by one to avoid services to go down (when only 2 replicas)
    }
    os_sku               = "AzureLinux"
    kubelet_disk_type    = "OS"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
    orchestrator_version = local.aks_clusters["publick8s"].kubernetes_version
    auto_scaling_enabled = true
    min_count            = 4
    max_count            = 6
    vnet_subnet_id       = data.azurerm_subnet.publick8s.id
    tags                 = local.default_tags
    zones                = [1, 2, 3]
    # No custom node_taints
  }

  tags = local.default_tags
}

# Allow cluster to manage network resources in the associated subnets
# It is used for managing LBs of the public and private ingress controllers
resource "azurerm_role_assignment" "publick8s_subnets_networkcontributor" {
  for_each = toset([
    data.azurerm_subnet.publick8s.id, # Node pool
  ])
  scope                            = each.key
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Each public load balancer used by this cluster is setup with a locked public IP.
# Using a pre-determined public IP eases DNS setup and changes, but requires cluster to have the "Network Contributor" role on the IP.
locals {
  publick8s_public_ips = {
    "publick8s-public-ipv4" = "IPv4" # Ingress for HTTP services
    "publick8s-public-ipv6" = "IPv6" # Ingress for HTTP services
    "publick8s-ldap-ipv4"   = "IPv4" # LDAP for its own LB (cannot share public IP across LBs)
  }
}
resource "azurerm_public_ip" "publick8s_ips" {
  for_each = local.publick8s_public_ips

  name                = each.key
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = each.value
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "publick8s_ips" {
  for_each = local.publick8s_public_ips

  name       = each.key
  scope      = azurerm_public_ip.publick8s_ips[each.key].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}
resource "azurerm_role_assignment" "publick8s_ips_networkcontributor" {
  for_each = local.publick8s_public_ips

  scope                            = azurerm_public_ip.publick8s_ips[each.key].id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

################################
### Kubernetes Resources below
################################
resource "kubernetes_storage_class" "publick8s_statically_provisioned" {
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  provider               = kubernetes.publick8s
  allow_volume_expansion = true
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "publick8s_admin_sa" {
  providers = {
    kubernetes = kubernetes.publick8s
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.publick8s.name
  cluster_hostname           = local.aks_clusters_outputs.publick8s.cluster_hostname
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.publick8s.kube_config.0.cluster_ca_certificate
}

# PVCs (see below) needs their namespaces
resource "kubernetes_namespace" "publick8s_namespaces" {
  provider = kubernetes.publick8s
  for_each = toset(sort(distinct(concat(
    [for key, value in local.aks_clusters["publick8s"].azurefile_volumes : lookup(value, "pvc_namespace", key)],
    [for key, value in local.aks_clusters["publick8s"].azuredisk_volumes : lookup(value, "pvc_namespace", key)],
    ["data-storage-jenkins-io"],
  ))))

  metadata {
    name = each.key
    labels = {
      name = each.key
    }
  }
}

# PVs (see below) need storage secret keys when using CSI Azure file (as workload identity cannot be used with AKS CSI driver)
resource "kubernetes_secret" "publick8s_azurefiles" {
  provider = kubernetes.publick8s
  for_each = toset(sort(distinct(concat(
    [for key, value in local.aks_clusters["publick8s"].azurefile_volumes : key if can(value["secret_name"])],
  ))))

  metadata {
    name      = local.aks_clusters["publick8s"].azurefile_volumes[each.key].secret_name
    namespace = local.aks_clusters["publick8s"].azurefile_volumes[each.key].secret_namespace
  }

  data = {
    # Convention: secret name and storage account name are the same (it is namespaced and it makes no sense to duplicate on a given NS for many PVCs: we reuse)
    azurestorageaccountname = local.aks_clusters["publick8s"].azurefile_volumes[each.key].secret_name
    azurestorageaccountkey  = local.aks_clusters["publick8s"].azurefile_volumes[each.key].storage_account_key
  }

  type = "Opaque"
}
resource "kubernetes_secret" "publick8s_azurefile_jenkins_io_storage_account" {
  provider = kubernetes.publick8s

  metadata {
    name      = "data-storage-jenkins-io-storage-account"
    namespace = kubernetes_namespace.publick8s_namespaces["data-storage-jenkins-io"].metadata[0].name
  }

  data = {
    azurestorageaccountname = azurerm_storage_account.data_storage_jenkins_io.name
    azurestorageaccountkey  = azurerm_storage_account.data_storage_jenkins_io.primary_access_key
  }

  type = "Opaque"
}

# We assume usage of the "big" NFS data storage as default (unless the local specifies other values for edge cases)
# Note: when deleting a PV, you have to remove the 'metadata.finalizers' key (usually when deletion is stuck)
resource "kubernetes_persistent_volume" "publick8s_azurefiles" {
  provider = kubernetes.publick8s
  for_each = local.aks_clusters["publick8s"].azurefile_volumes

  metadata {
    # Same name as the namespace (easier to map PVs which are NOT namespaced)
    name = each.key
  }
  spec {
    capacity = {
      storage = "${lookup(each.value, "capacity", azurerm_storage_share.data_storage_jenkins_io.quota)}Gi"
    }
    access_modes                     = lookup(each.value, "access_modes", ["ReadOnlyMany"])
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.publick8s_statically_provisioned.id
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {
      # Default: PV name and NS names are the same (easier to map PVs which are NOT namespaced)
      # But we allow using a custom PVC namespace when the key (e.?g. the PV name) differs
      namespace = lookup(each.value, "pvc_namespace", each.key)
      name      = each.key
    }
    mount_options = lookup(each.value, "mount_options", [
      "nconnect=4", # Mandatory value (4) for Premium Azure File Share NFS 4.1. Increasing require using NetApp NFS instead ($$$)
      "noresvport", # ref. https://linux.die.net/man/5/nfs
      "actimeo=10", # Data is changed quite often
      "cto",        # Ensure data consistency at the cost of slower I/O
    ])
    persistent_volume_source {
      csi {
        driver  = "file.csi.azure.com"
        fs_type = "ext4"
        # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
        volume_handle = lookup(each.value, "volume_handle", "${azurerm_storage_account.data_storage_jenkins_io.resource_group_name}#${azurerm_storage_account.data_storage_jenkins_io.name}#${azurerm_storage_share.data_storage_jenkins_io.name}")
        read_only     = lookup(each.value, "read_only", true)
        volume_attributes = lookup(each.value, "volume_attributes", {
          protocol      = "nfs"
          resourceGroup = azurerm_storage_account.data_storage_jenkins_io.resource_group_name
          shareName     = azurerm_storage_share.data_storage_jenkins_io.name
        })
        node_stage_secret_ref {
          name      = lookup(each.value, "secret_name", kubernetes_secret.publick8s_azurefile_jenkins_io_storage_account.metadata[0].name)
          namespace = lookup(each.value, "secret_namespace", kubernetes_secret.publick8s_azurefile_jenkins_io_storage_account.metadata[0].namespace)
        }
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "publick8s_azurefiles" {
  provider = kubernetes.publick8s
  for_each = local.aks_clusters["publick8s"].azurefile_volumes

  metadata {
    # Mapping 1:1 with PV and PVC using names (to allow claim_ref to work on PV)
    name = kubernetes_persistent_volume.publick8s_azurefiles[each.key].metadata[0].name
    # Default: PV name and NS names are the same (easier to map PVs which are NOT namespaced)
    # But we allow using a custom PVC namespace when the key (e.?g. the PV name) differs
    namespace = lookup(each.value, "pvc_namespace", each.key)
  }
  spec {
    access_modes       = kubernetes_persistent_volume.publick8s_azurefiles[each.key].spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.publick8s_azurefiles[each.key].metadata[0].name
    storage_class_name = kubernetes_persistent_volume.publick8s_azurefiles[each.key].spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.publick8s_azurefiles[each.key].spec[0].capacity.storage
      }
    }
  }
}

# Note: when deleting a PV, you have to remove the 'metadata.finalizers' key (usually when deletion is stuck)
resource "kubernetes_persistent_volume" "publick8s_datadisks" {
  provider = kubernetes.publick8s
  for_each = local.aks_clusters["publick8s"].azuredisk_volumes

  metadata {
    # Disk name is the last element from the Azure ID string
    name = element(split("/", each.value.disk_id), "-1")
  }
  spec {
    capacity = {
      storage = "${each.value.disk_size}Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class.publick8s_statically_provisioned.id
    persistent_volume_source {
      csi {
        driver        = "disk.csi.azure.com"
        volume_handle = each.value.disk_id
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim" "publick8s_datadisks" {
  provider = kubernetes.publick8s
  for_each = local.aks_clusters["publick8s"].azuredisk_volumes

  metadata {
    # Disk name is the last element from the Azure ID string
    name = element(split("/", each.value.disk_id), "-1")
    # Default: PV name and NS names are the same (easier to map PVs which are NOT namespaced)
    # But we allow using a custom PVC namespace when the key (e.?g. the PV name) differs
    namespace = lookup(each.value, "pvc_namespace", each.key)
  }
  spec {
    access_modes       = kubernetes_persistent_volume.publick8s_datadisks[each.key].spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.publick8s_datadisks[each.key].metadata.0.name
    storage_class_name = kubernetes_persistent_volume.publick8s_datadisks[each.key].spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.publick8s_datadisks[each.key].spec[0].capacity.storage
      }
    }
  }
}
# Permissions/Role required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "publick8s_datadisks" {
  for_each = local.aks_clusters["publick8s"].azuredisk_volumes

  name  = "publick8s-read-disk-${each.key}"
  scope = each.value.disk_rg_id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "publick8s_datadisks" {
  for_each = local.aks_clusters["publick8s"].azuredisk_volumes

  scope              = each.value.disk_rg_id
  role_definition_id = azurerm_role_definition.publick8s_datadisks[each.key].role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
}

# Retrieve effective outbound IPs
data "azurerm_public_ip" "publick8s_lb_outbound" {
  ## Disable this resource when running in terratest
  # to avoid the error "The "for_each" set includes values derived from resource attributes that cannot be determined until apply"
  for_each = var.terratest ? toset([]) : toset(concat(flatten(azurerm_kubernetes_cluster.publick8s.network_profile[*].load_balancer_profile[*].effective_outbound_ips)))

  name                = element(split("/", each.key), "-1")
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
}
