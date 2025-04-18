resource "azurerm_resource_group" "privatek8s" {
  name     = "prod-privatek8s"
  location = var.location
  tags     = local.default_tags
}

resource "random_pet" "suffix_privatek8s" {
  # You want to taint this resource in order to get a new pet
}

data "azurerm_subnet" "privatek8s_tier" {
  name                 = "privatek8s-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

data "azurerm_subnet" "privatek8s_release_tier" {
  name                 = "privatek8s-release-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

data "azurerm_subnet" "privatek8s_infra_ci_controller_tier" {
  name                 = "privatek8s-infraci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

data "azurerm_subnet" "privatek8s_release_ci_controller_tier" {
  name                 = "privatek8s-releaseci-ctrl-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}


#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "privatek8s" {
  name                              = local.aks_clusters["privatek8s"].name
  location                          = azurerm_resource_group.privatek8s.location
  resource_group_name               = azurerm_resource_group.privatek8s.name
  kubernetes_version                = local.aks_clusters["privatek8s"].kubernetes_version
  dns_prefix                        = local.aks_clusters["privatek8s"].name
  role_based_access_control_enabled = true # default value but made explicit to please trivy

  upgrade_override {
    # TODO: disable to avoid "surprise" upgrades
    force_upgrade_enabled = true
  }

  api_server_access_profile {
    authorized_ip_ranges = setunion(
      formatlist(
        "%s/32",
        flatten(
          concat(
            [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
            # privatek8s outbound IPs (traffic routed through gateways or outbound LBs)
            module.jenkins_infra_shared_data.outbound_ips["privatek8s.jenkins.io"],
            module.jenkins_infra_shared_data.outbound_ips["infracijenkinsioagents1.jenkins.io"],
          )
        )
      ),
      data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
    )
  }

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    outbound_type     = "loadBalancer"
    load_balancer_sku = "standard"
    load_balancer_profile {
      outbound_ports_allocated  = "1088" # Max 58 Nodes, <64000 total
      idle_timeout_in_minutes   = "4"
      managed_outbound_ip_count = "1"
    }
  }

  default_node_pool {
    name    = "syspool"
    vm_size = "Standard_D2as_v4"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "Ubuntu"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 50 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dav4-dasv4-series#dasv4-series (depends on the instance size)
    orchestrator_version = local.aks_clusters["privatek8s"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 3
    vnet_subnet_id       = data.azurerm_subnet.privatek8s_tier.id
    tags                 = local.default_tags
    zones                = [3]
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "linuxpool" {
  name    = "linuxpool"
  vm_size = "Standard_D4s_v3"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 100 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 5
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_tier.id

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# nodepool dedicated for the infra.ci.jenkins.io controller
resource "azurerm_kubernetes_cluster_node_pool" "infraci_controller" {
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
  zones                 = [1] # Linux arm64 VMs are only available in the Zone 1 in this region (undocumented by Azure)
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
resource "azurerm_kubernetes_cluster_node_pool" "releaseci_controller" {
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
  zones                 = [1] # Linux arm64 VMs are only available in the Zone 1 in this region (undocumented by Azure)
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
resource "azurerm_kubernetes_cluster_node_pool" "releasepool" {
  name    = "releasepool"
  vm_size = "Standard_D8s_v3" # 8 vCPU 32 GiB RAM
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 200 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_release_tier.id
  node_taints = [
    "jenkins=release.ci.jenkins.io:NoSchedule",
  ]

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "windows2019pool" {
  name    = "w2019"
  vm_size = "Standard_D4s_v3" # 4 vCPU 16 GiB RAM
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 100 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s"].kubernetes_version
  os_type               = "Windows"
  os_sku                = "Windows2019"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [3]
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

data "azurerm_kubernetes_cluster" "privatek8s" {
  name                = local.aks_clusters["privatek8s"].name
  resource_group_name = azurerm_resource_group.privatek8s.name
}

# Allow cluster to manage network resources in the privatek8s_tier subnet
# It is used for managing the LBs of the public ingress controller
resource "azurerm_role_assignment" "privatek8s_networkcontributor" {
  scope                            = data.azurerm_subnet.privatek8s_tier.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage network resources in the private_vnet_data_tier subnet
# It is used for managing the LB of the private ingress controller
resource "azurerm_role_assignment" "datatier_networkcontributor" {
  scope                            = data.azurerm_subnet.private_vnet_data_tier.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage the public IP public_privatek8s
# It is used for managing the public IP of the LBs of the public ingress controller
resource "azurerm_role_assignment" "publicip_networkcontributor" {
  scope                            = azurerm_public_ip.public_privatek8s.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage get.jenkins.io storage account
## TODO: for what usage?
resource "azurerm_role_assignment" "getjenkinsio_storage_account_contributor" {
  scope                            = azurerm_storage_account.get_jenkins_io.id
  role_definition_name             = "Storage Account Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "kubernetes_storage_class" "managed_csi_premium_retain" {
  metadata {
    name = "managed-csi-premium-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
  provider = kubernetes.privatek8s
}

resource "kubernetes_storage_class" "azurefile_csi_premium_retain" {
  metadata {
    name = "azurefile-csi-premium-retain"
  }
  storage_provisioner = "file.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
  mount_options = ["dir_mode=0777", "file_mode=0777", "uid=1000", "gid=1000", "mfsymlinks", "nobrl"]
  provider      = kubernetes.privatek8s
}

resource "kubernetes_storage_class" "managed_csi_premium_ZRS_retain_private" {
  metadata {
    name = "managed-csi-premium-zrs-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_ZRS"
  }
  provider               = kubernetes.privatek8s
  allow_volume_expansion = true
}

# https://learn.microsoft.com/en-us/java/api/com.microsoft.azure.management.storage.skuname?view=azure-java-legacy#field-summary
resource "kubernetes_storage_class" "managed_csi_standard_ZRS_retain_private" {
  metadata {
    name = "managed-csi-standard-zrs-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = " Standard_ZRS"
  }
  provider               = kubernetes.privatek8s
  allow_volume_expansion = true
}

# TODO: remove this class once all PV/PVCs have been patched
resource "kubernetes_storage_class" "statically_provisionned_privatek8s" {
  metadata {
    name = "statically-provisionned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  provider               = kubernetes.privatek8s
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "statically_provisioned_privatek8s" {
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  provider               = kubernetes.privatek8s
  allow_volume_expansion = true
}

# Used later by the load balancer deployed on the cluster, see https://github.com/jenkins-infra/kubernetes-management/config/privatek8s.yaml
resource "azurerm_public_ip" "public_privatek8s" {
  name                = "public-privatek8s"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "public_privatek8s_publicip" {
  name       = "public-privatek8s-publicip"
  scope      = azurerm_public_ip.public_privatek8s.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when privatek8s is removed"
}

resource "azurerm_dns_a_record" "public_privatek8s" {
  name                = "public.privatek8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.public_privatek8s.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "private_privatek8s" {
  name                = "private.privatek8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = ["10.248.1.5"] # External IP of the private-nginx ingress LoadBalancer, created by https://github.com/jenkins-infra/kubernetes-management/blob/54a0d4aa72b15f4236abcfbde00a080905bbb890/clusters/privatek8s.yaml#L112-L118
  tags                = local.default_tags
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "privatek8s_admin_sa" {
  providers = {
    kubernetes = kubernetes.privatek8s
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.privatek8s.name
  cluster_hostname           = azurerm_kubernetes_cluster.privatek8s.kube_config.0.host
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.privatek8s.kube_config.0.cluster_ca_certificate
}
output "kubeconfig_management_privatek8s" {
  sensitive = true
  value     = module.privatek8s_admin_sa.kubeconfig
}

# Retrieve effective outbound IPs
data "azurerm_public_ip" "privatek8s_lb_outbound" {
  ## Disable this resource when running in terratest
  # to avoid the error "The "for_each" set includes values derived from resource attributes that cannot be determined until apply"
  for_each = var.terratest ? toset([]) : toset(concat(flatten(azurerm_kubernetes_cluster.privatek8s.network_profile[*].load_balancer_profile[*].effective_outbound_ips)))

  name                = element(split("/", each.key), "-1")
  resource_group_name = azurerm_kubernetes_cluster.privatek8s.node_resource_group
}
