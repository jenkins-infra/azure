resource "azurerm_resource_group" "privatek8s_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "privatek8s-sponsorship"
  location = var.location
  tags     = local.default_tags
}

data "azurerm_subnet" "privatek8s_sponsorship_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

data "azurerm_subnet" "privatek8s_sponsorship_release_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-release-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

data "azurerm_subnet" "privatek8s_sponsorship_infra_ci_controller_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-infraci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

data "azurerm_subnet" "privatek8s_sponsorship_release_ci_controller_tier" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "privatek8s-sponsorship-releaseci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "privatek8s_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = local.aks_clusters["privatek8s_sponsorship"].name
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = local.aks_clusters["privatek8s_sponsorship"].name
  location                            = azurerm_resource_group.privatek8s_sponsorship.location
  resource_group_name                 = azurerm_resource_group.privatek8s_sponsorship.name
  kubernetes_version                  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  role_based_access_control_enabled   = true # default value but made explicit to please trivy

  ## TODO need to understand how it's handled `upgrade_override`
  #   upgrade_override {
  #     # TODO: disable to avoid "surprise" upgrades
  #     force_upgrade_enabled = true
  #   }

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard" # Required to customize the outbound type
    pod_cidr            = local.aks_clusters.privatek8s_sponsorship.pod_cidr
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
    os_disk_size_gb      = 75 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/dasv5-dadsv5-series#dadsv5-series (depends on the instance size)
    orchestrator_version = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.privatek8s_sponsorship_tier.id
    tags                 = local.default_tags
    zones                = [3]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "linuxpool_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "linuxpool"
  vm_size  = "Standard_D4s_v3"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 100 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsorship.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 5
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsorship_tier.id

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# nodepool dedicated for the infra.ci.jenkins.io controller
resource "azurerm_kubernetes_cluster_node_pool" "infraci_controller_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "infracictrl"
  vm_size  = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsorship.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 2
  zones                 = [1] # same zones as infraci agents to avoid network cost TODO track with updatecli
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsorship_infra_ci_controller_tier.id

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
resource "azurerm_kubernetes_cluster_node_pool" "releaseci_controller_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "releacictrl"
  vm_size  = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  upgrade_settings {
    max_surge = "10%"
  }
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsorship.id
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 2
  zones                 = [3] # same as releasepool
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsorship_release_ci_controller_tier.id

  node_taints = [
    "jenkins=release.ci.jenkins.io:NoSchedule",
    "jenkins-component=controller:NoSchedule"
  ]
  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}
resource "azurerm_kubernetes_cluster_node_pool" "releasepool_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "releasepool"
  vm_size  = "Standard_D8s_v3" # 8 vCPU 32 GiB RAM
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 200 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsorship.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [3] # same as release controller
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsorship_release_tier.id
  node_taints = [
    "jenkins=release.ci.jenkins.io:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "windows2019pool_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "w2019"
  vm_size  = "Standard_D4s_v3" # 4 vCPU 16 GiB RAM
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 100 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  os_type               = "Windows"
  os_sku                = "Windows2019"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsorship.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsorship_release_tier.id
  node_taints = [
    "os=windows:NoSchedule",
    "jenkins=release.ci.jenkins.io:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# data "azurerm_kubernetes_cluster" "privatek8s" {
#   name                = local.aks_clusters["privatek8s"].name
#   resource_group_name = azurerm_resource_group.privatek8s.name
# }

# Allow cluster to manage LBs in the privatek8s_sponsorship_tier-tier subnet (Public LB)
resource "azurerm_role_assignment" "privatek8s_sponsorship_networkcontributor" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = data.azurerm_subnet.privatek8s_sponsorship_tier.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage LBs in the data-tier subnet (internal LBs)
resource "azurerm_role_assignment" "datatier_networkcontributor_sponsorship" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = data.azurerm_subnet.private_vnet_data_tier.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage private IP
resource "azurerm_role_assignment" "publicip_networkcontributor_sponsorship" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = azurerm_public_ip.public_privatek8s_sponsorship.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage get.jenkins.io storage account
resource "azurerm_role_assignment" "getjenkinsio_storage_account_contributor_sponsorship" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = azurerm_storage_account.get_jenkins_io.id
  role_definition_name             = "Storage Account Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "kubernetes_storage_class" "managed_csi_premium_retain_sponsorship" {
  provider = kubernetes.privatek8s_sponsorship
  metadata {
    name = "managed-csi-premium-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
}

resource "kubernetes_storage_class" "azurefile_csi_premium_retain_sponsorship" {
  provider = kubernetes.privatek8s_sponsorship
  metadata {
    name = "azurefile-csi-premium-retain"
  }
  storage_provisioner = "file.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
  mount_options = ["dir_mode=0777", "file_mode=0777", "uid=1000", "gid=1000", "mfsymlinks", "nobrl"]

}

resource "kubernetes_storage_class" "managed_csi_premium_ZRS_retain_private_sponsorship" {
  provider = kubernetes.privatek8s_sponsorship
  metadata {
    name = "managed-csi-premium-zrs-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_ZRS"
  }
  allow_volume_expansion = true
}

# https://learn.microsoft.com/en-us/java/api/com.microsoft.azure.management.storage.skuname?view=azure-java-legacy#field-summary
resource "kubernetes_storage_class" "managed_csi_standard_ZRS_retain_private_sponsorship" {
  provider = kubernetes.privatek8s_sponsorship
  metadata {
    name = "managed-csi-standard-zrs-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = " Standard_ZRS"
  }
  allow_volume_expansion = true
}

# TODO: remove this class once all PV/PVCs have been patched
resource "kubernetes_storage_class" "statically_provisionned_privatek8s_sponsorship" {
  provider = kubernetes.privatek8s_sponsorship
  metadata {
    name = "statically-provisionned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "statically_provisioned_privatek8s_sponsorship" {
  provider = kubernetes.privatek8s_sponsorship
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
}

# Used later by the load balancer deployed on the cluster, see https://github.com/jenkins-infra/kubernetes-management/config/privatek8s.yaml
resource "azurerm_public_ip" "public_privatek8s_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "public-privatek8s"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "public_privatek8s_sponsorship_publicip" {
  provider   = azurerm.jenkins-sponsorship
  name       = "public-privatek8s-publicip"
  scope      = azurerm_public_ip.public_privatek8s_sponsorship.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when privatek8s is removed"
}

resource "azurerm_dns_a_record" "public_privatek8s_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "public.privatek8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.public_privatek8s_sponsorship.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "private_privatek8s_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "private.privatek8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  ### TODO UPDATE
  records = ["10.248.1.5"] # External IP of the private-nginx ingress LoadBalancer, created by https://github.com/jenkins-infra/kubernetes-management/blob/54a0d4aa72b15f4236abcfbde00a080905bbb890/clusters/privatek8s.yaml#L112-L118
  tags    = local.default_tags
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "privatek8s_sponsorship_admin_sa" {
  providers = {
    kubernetes = kubernetes.privatek8s_sponsorship
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.privatek8s_sponsorship.name
  cluster_hostname           = azurerm_kubernetes_cluster.privatek8s_sponsorship.kube_config.0.host
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.privatek8s_sponsorship.kube_config.0.cluster_ca_certificate
}
output "kubeconfig_management_privatek8s_sponsorship" {
  sensitive = true
  value     = module.privatek8s_sponsorship_admin_sa.kubeconfig
}

# Retrieve effective outbound IPs
data "azurerm_public_ip" "privatek8s_sponsorship_lb_outbound" {
  ## Disable this resource when running in terratest
  # to avoid the error "The "for_each" set includes values derived from resource attributes that cannot be determined until apply"
  for_each = var.terratest ? toset([]) : toset(concat(flatten(azurerm_kubernetes_cluster.privatek8s_sponsorship.network_profile[*].load_balancer_profile[*].effective_outbound_ips)))

  name                = element(split("/", each.key), "-1")
  resource_group_name = azurerm_kubernetes_cluster.privatek8s_sponsorship.node_resource_group
}
