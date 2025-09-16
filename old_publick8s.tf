###### TODO delete legacy resources above once migration to the new `publick8s` cluster is finished
resource "random_pet" "suffix_publick8s" {
  # You want to taint this resource in order to get a new pet
}

moved {
  from = azurerm_kubernetes_cluster.publick8s
  to   = azurerm_kubernetes_cluster.old_publick8s
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

moved {
  from = data.azurerm_kubernetes_cluster.publick8s
  to   = data.azurerm_kubernetes_cluster.old_publick8s
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
moved {
  from = azurerm_role_assignment.publick8s_public_vnet_networkcontributor
  to   = azurerm_role_assignment.old_publick8s_public_vnet_networkcontributor
}
# Allow cluster to manage LBs in the publick8s-tier subnet (Public LB)
resource "azurerm_role_assignment" "old_publick8s_public_vnet_networkcontributor" {
  scope                            = data.azurerm_virtual_network.public.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
# Allow cluster to manage Azure PLS if it's in the same subnet as the the cluster itself
data "azurerm_nat_gateway" "publick8s_outbound" {
  resource_group_name = data.azurerm_virtual_network.public.resource_group_name
  name                = "publick8s-outbound"
}
moved {
  from = azurerm_role_definition.publick8s_outbound_gateway
  to   = azurerm_role_definition.old_publick8s_outbound_gateway
}
resource "azurerm_role_definition" "old_publick8s_outbound_gateway" {
  name  = "publick8s_outbount_gateway"
  scope = data.azurerm_nat_gateway.publick8s_outbound.id

  permissions {
    actions = ["Microsoft.Network/natGateways/join/action"]
  }
}
moved {
  from = azurerm_role_assignment.publick8s_nat_gateway
  to   = azurerm_role_assignment.old_publick8s_nat_gateway
}
resource "azurerm_role_assignment" "old_publick8s_nat_gateway" {
  scope                            = data.azurerm_nat_gateway.publick8s_outbound.id
  role_definition_id               = azurerm_role_definition.old_publick8s_outbound_gateway.role_definition_resource_id
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
moved {
  from = azurerm_role_assignment.publick8s_ipv4_networkcontributor
  to   = azurerm_role_assignment.old_publick8s_ipv4_networkcontributor
}
# Allow cluster to manage publick8s_ipv4
resource "azurerm_role_assignment" "old_publick8s_ipv4_networkcontributor" {
  scope                            = azurerm_public_ip.old_publick8s_ipv4.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
moved {
  from = azurerm_role_assignment.ldap_jenkins_io_ipv4_networkcontributor
  to   = azurerm_role_assignment.old_ldap_jenkins_io_ipv4_networkcontributor
}
# Allow cluster to manage ldap_jenkins_io_ipv4
resource "azurerm_role_assignment" "old_ldap_jenkins_io_ipv4_networkcontributor" {
  scope                            = azurerm_public_ip.old_ldap_jenkins_io_ipv4.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
moved {
  from = azurerm_role_assignment.publick8s_ipv6_networkcontributor
  to   = azurerm_role_assignment.old_publick8s_ipv6_networkcontributor
}
# Allow cluster to manage publick8s_ipv6
resource "azurerm_role_assignment" "old_publick8s_ipv6_networkcontributor" {
  scope                            = azurerm_public_ip.old_publick8s_ipv6.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.old_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
moved {
  from = azurerm_role_assignment.public_ips_networkcontributor
  to   = azurerm_role_assignment.old_public_ips_networkcontributor
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
moved {
  from = azurerm_public_ip.publick8s_ipv4
  to   = azurerm_public_ip.old_publick8s_ipv4
}
resource "azurerm_public_ip" "old_publick8s_ipv4" {
  name                = "public-publick8s-ipv4"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv4"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
moved {
  from = azurerm_management_lock.publick8s_ipv4
  to   = azurerm_management_lock.old_publick8s_ipv4
}
resource "azurerm_management_lock" "old_publick8s_ipv4" {
  name       = "public-publick8s-ipv4"
  scope      = azurerm_public_ip.old_publick8s_ipv4.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}

# The LDAP service deployed on this cluster is using TCP not HTTP/HTTPS, it needs its own load balancer
# Setting it with this determined public IP will ease DNS setup and changes
moved {
  from = azurerm_public_ip.ldap_jenkins_io_ipv4
  to   = azurerm_public_ip.old_ldap_jenkins_io_ipv4
}
resource "azurerm_public_ip" "old_ldap_jenkins_io_ipv4" {
  name                = "ldap-jenkins-io-ipv4"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv4"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
moved {
  from = azurerm_management_lock.ldap_jenkins_io_ipv4
  to   = azurerm_management_lock.old_ldap_jenkins_io_ipv4
}
resource "azurerm_management_lock" "old_ldap_jenkins_io_ipv4" {
  name       = "ldap-jenkins-io-ipv4"
  scope      = azurerm_public_ip.old_ldap_jenkins_io_ipv4.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}
moved {
  from = azurerm_public_ip.publick8s_ipv6
  to   = azurerm_public_ip.old_publick8s_ipv6
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
moved {
  from = azurerm_management_lock.publick8s_ipv6
  to   = azurerm_management_lock.old_publick8s_ipv6
}
resource "azurerm_management_lock" "old_publick8s_ipv6" {
  name       = "public-publick8s-ipv6"
  scope      = azurerm_public_ip.old_publick8s_ipv6.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}
moved {
  from = azurerm_management_lock.publick8s_ipv6
  to   = azurerm_management_lock.old_publick8s_ipv6
}

moved {
  from = module.publick8s_admin_sa
  to   = module.old_publick8s_admin_sa
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
