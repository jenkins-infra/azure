resource "azurerm_resource_group" "publick8s" {
  name     = "publick8s"
  location = var.location
  tags     = local.default_tags
}

resource "random_pet" "suffix_publick8s" {
  # You want to taint this resource in order to get a new pet
}

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

locals {
  publick8s_compute_zones = [3]
}

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "publick8s" {
  name                              = "publick8s-${random_pet.suffix_publick8s.id}"
  location                          = azurerm_resource_group.publick8s.location
  resource_group_name               = azurerm_resource_group.publick8s.name
  kubernetes_version                = local.kubernetes_versions["publick8s"]
  dns_prefix                        = "publick8s-${random_pet.suffix_publick8s.id}"
  role_based_access_control_enabled = true # default value, added to please tfsec
  api_server_access_profile {
    authorized_ip_ranges = setunion(
      # admins
      formatlist(
        "%s/32",
        flatten(
          concat(
            [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
          )
        )
      ),
      # private VPN access
      data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
      # privatek8s nodes subnet
      data.azurerm_subnet.privatek8s_tier.address_prefixes,
      [local.privatek8s_outbound_ip_cidr],
      # trusted.ci subnet (UC agents need to execute mirrorbits scans)
      formatlist("%s/32", module.jenkins_infra_shared_data.outbound_ips["trusted.ci.jenkins.io"]),
    )
  }

  #trivy:ignore:azure-container-configured-network-policy
  network_profile {
    network_plugin = "kubenet"
    # These ranges must NOT overlap with any of the subnets
    pod_cidrs   = ["10.100.0.0/16", "fd12:3456:789a::/64"]
    ip_versions = ["IPv4", "IPv6"]
  }

  default_node_pool {
    name                        = "systempool"
    vm_size                     = "Standard_D2as_v4" # 2 vCPU, 8 GB RAM, 16 GB disk, 4000 IOPS
    os_disk_type                = "Ephemeral"
    os_disk_size_gb             = 30
    orchestrator_version        = local.kubernetes_versions["publick8s"]
    node_count                  = 1
    vnet_subnet_id              = data.azurerm_subnet.publick8s_tier.id
    tags                        = local.default_tags
    temporary_name_for_rotation = "systempool2"
    zones                       = local.publick8s_compute_zones
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "systempool_secondary" {
  name                        = "systempool3"
  mode                        = "System"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  vm_size                     = "Standard_D2as_v4" # 2 vCPU, 8 GB RAM, 16 GB disk, 4000 IOPS
  kubelet_disk_type           = "OS"
  os_disk_type                = "Ephemeral"
  os_disk_size_gb             = 50
  orchestrator_version        = local.kubernetes_versions["publick8s"]
  enable_auto_scaling         = false
  node_count                  = 1
  vnet_subnet_id              = data.azurerm_subnet.publick8s_tier.id
  tags                        = local.default_tags
  zones                       = local.publick8s_compute_zones

  node_taints = [
    "CriticalAddonsOnly=true:NoSchedule",
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "x86small" {
  name                  = "x86small"
  vm_size               = "Standard_D4s_v3" # 4 vCPU, 16 GB RAM, 32 GB disk, 8 000 IOPS
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 100 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.kubernetes_versions["publick8s"]
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 10
  zones                 = local.publick8s_compute_zones
  vnet_subnet_id        = data.azurerm_subnet.publick8s_tier.id

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "x86medium" {
  name                  = "x86medium"
  vm_size               = "Standard_D8s_v3" # 8 vCPU, 32 GB RAM, 64 GB disk, 16 000 IOPS
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 200 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.kubernetes_versions["publick8s"]
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  enable_auto_scaling   = false
  zones                 = local.publick8s_compute_zones
  vnet_subnet_id        = data.azurerm_subnet.publick8s_tier.id

  lifecycle {
    ignore_changes = [
      node_count, # as per https://github.com/jenkins-infra/helpdesk/issues/3827
    ]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "arm64small2" {
  name                  = "arm64small2"
  vm_size               = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.kubernetes_versions["publick8s"]
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  enable_auto_scaling   = true
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
resource "azurerm_role_assignment" "publick8s_networkcontributor" {
  scope                            = data.azurerm_subnet.publick8s_tier.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage LBs in the public-vnet-data-tier subnet (internal LBs)
resource "azurerm_role_assignment" "public_vnet_data_tier_networkcontributor" {
  scope                            = data.azurerm_subnet.public_vnet_data_tier.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage publick8s_ipv4
resource "azurerm_role_assignment" "publick8s_ipv4_networkcontributor" {
  scope                            = azurerm_public_ip.publick8s_ipv4.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage ldap_jenkins_io_ipv4
resource "azurerm_role_assignment" "ldap_jenkins_io_ipv4_networkcontributor" {
  scope                            = azurerm_public_ip.ldap_jenkins_io_ipv4.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage publick8s_ipv6
resource "azurerm_role_assignment" "publick8s_ipv6_networkcontributor" {
  scope                            = azurerm_public_ip.publick8s_ipv6.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
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
  provider               = kubernetes.publick8s
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
  provider               = kubernetes.publick8s
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
  provider      = kubernetes.publick8s
}

# Used later by the load balancer deployed on the cluster, see https://github.com/jenkins-infra/kubernetes-management/config/publick8s.yaml
resource "azurerm_public_ip" "publick8s_ipv4" {
  name                = "public-publick8s-ipv4"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv4"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "publick8s_ipv4" {
  name       = "public-publick8s-ipv4"
  scope      = azurerm_public_ip.publick8s_ipv4.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}

# The LDAP service deployed on this cluster is using TCP not HTTP/HTTPS, it needs its own load balancer
# Setting it with this determined public IP will ease DNS setup and changes
resource "azurerm_public_ip" "ldap_jenkins_io_ipv4" {
  name                = "ldap-jenkins-io-ipv4"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv4"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "ldap_jenkins_io_ipv4" {
  name       = "ldap-jenkins-io-ipv4"
  scope      = azurerm_public_ip.ldap_jenkins_io_ipv4.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}

resource "azurerm_public_ip" "publick8s_ipv6" {
  name                = "public-publick8s-ipv6"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv6"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "publick8s_ipv6" {
  name       = "public-publick8s-ipv6"
  scope      = azurerm_public_ip.publick8s_ipv6.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}

resource "azurerm_dns_a_record" "public_publick8s" {
  name                = "public.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.publick8s_ipv4.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_aaaa_record" "public_publick8s" {
  name                = "public.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.publick8s_ipv6.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "private_publick8s" {
  name                = "private.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = ["10.245.1.4"] # External IP of the private-nginx ingress LoadBalancer, created by https://github.com/jenkins-infra/kubernetes-management/blob/54a0d4aa72b15f4236abcfbde00a080905bbb890/clusters/publick8s.yaml#L63-L69
  tags                = local.default_tags
}

output "publick8s_kube_config" {
  value     = azurerm_kubernetes_cluster.publick8s.kube_config_raw
  sensitive = true
}

output "publick8s_public_ipv4_address" {
  value = azurerm_public_ip.publick8s_ipv4.ip_address
}

output "publick8s_public_ipv6_address" {
  value = azurerm_public_ip.publick8s_ipv6.ip_address
}

output "ldap_jenkins_io_ipv4_address" {
  value = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "publick8s_admin_sa" {
  providers = {
    kubernetes = kubernetes.publick8s
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.publick8s.name
  cluster_hostname           = azurerm_kubernetes_cluster.publick8s.kube_config.0.host
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.publick8s.kube_config.0.cluster_ca_certificate
}

output "kubeconfig_publick8s" {
  sensitive = true
  value     = module.publick8s_admin_sa.kubeconfig
}

output "publick8s_kube_config_command" {
  value = "az aks get-credentials --name ${azurerm_kubernetes_cluster.publick8s.name} --resource-group ${azurerm_kubernetes_cluster.publick8s.resource_group_name}"
}
