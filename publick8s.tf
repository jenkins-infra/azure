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

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "publick8s" {
  name                              = "publick8s-${random_pet.suffix_publick8s.id}"
  location                          = azurerm_resource_group.publick8s.location
  resource_group_name               = azurerm_resource_group.publick8s.name
  kubernetes_version                = local.kubernetes_versions["publick8s"]
  dns_prefix                        = "publick8s-${random_pet.suffix_publick8s.id}"
  role_based_access_control_enabled = true # default value but made explicit to please trivy
  api_server_access_profile {
    authorized_ip_ranges = setunion(
      # admins
      formatlist(
        "%s/32",
        flatten(
          concat(
            [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
            # privatek8s outbound IPs (traffic routed through gateways or outbound LBs)
            module.jenkins_infra_shared_data.outbound_ips["privatek8s.jenkins.io"],
            # publick8s outbound IPs (traffic routed through gateways or outbound LBs)
            module.jenkins_infra_shared_data.outbound_ips["publick8s.jenkins.io"],
            # trusted.ci subnet (UC agents need to execute mirrorbits scans)
            module.jenkins_infra_shared_data.outbound_ips["trusted.ci.jenkins.io"],
            module.jenkins_infra_shared_data.outbound_ips["trusted.sponsorship.ci.jenkins.io"],
            module.jenkins_infra_shared_data.outbound_ips["infracijenkinsioagents1.jenkins.io"],
          )
        )
      ),
      # private VPN access
      data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
      # privatek8s nodes subnet
      data.azurerm_subnet.privatek8s_tier.address_prefixes,
    )
  }

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
    orchestrator_version = local.kubernetes_versions["publick8s"]
    enable_auto_scaling  = true
    min_count            = 2
    max_count            = 4
    vnet_subnet_id       = data.azurerm_subnet.publick8s_tier.id
    tags                 = local.default_tags
    zones                = local.publick8s_compute_zones
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}


data "azurerm_kubernetes_cluster" "publick8s" {
  name                = "publick8s-${random_pet.suffix_publick8s.id}"
  resource_group_name = azurerm_resource_group.publick8s.name
}


resource "azurerm_kubernetes_cluster_node_pool" "x86small" {
  name    = "x86small"
  vm_size = "Standard_D4s_v3" # 4 vCPU, 16 GB RAM, 32 GB disk, 8 000 IOPS
  upgrade_settings {
    max_surge = "10%"
  }
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

resource "azurerm_kubernetes_cluster_node_pool" "arm64small2" {
  name    = "arm64small2"
  vm_size = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  upgrade_settings {
    max_surge = "10%"
  }
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

## TODO: remove once private ingress moved to private vnet
# Allow cluster to manage LBs in the public-vnet-data-tier subnet (internal LBs)
resource "azurerm_role_assignment" "public_vnet_data_tier_networkcontributor" {
  scope                            = data.azurerm_subnet.public_vnet_data_tier.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
# Allow cluster to manage LBs in the private-vnet-data-tier subnet (internal LBs)
resource "azurerm_role_assignment" "private_vnet_data_tier_networkcontributor" {
  scope                            = data.azurerm_subnet.private_vnet_data_tier.id
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

resource "azurerm_role_assignment" "public_ips_networkcontributor" {
  scope                            = azurerm_resource_group.prod_public_ips.id
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
  provider               = kubernetes.publick8s
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "statically_provisionned_publick8s" {
  metadata {
    name = "statically-provisionned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
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

# Cluster persistent data volumes
resource "azurerm_storage_account" "publick8s" {
  name                = "publick8spvdata"
  resource_group_name = azurerm_resource_group.publick8s.name
  location            = azurerm_resource_group.publick8s.location

  account_tier                      = "Standard"
  account_kind                      = "StorageV2"
  access_tier                       = "Hot"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec
  infrastructure_encryption_enabled = true
  enable_https_traffic_only         = true

  tags = local.default_tags

  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_rules {
    default_action = "Deny"
    ip_rules = flatten(
      concat(
        [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value],
      )
    )
    virtual_network_subnet_ids = [
      data.azurerm_subnet.publick8s_tier.id,
      data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.id, # infra.ci (Terraform management) Azure VM agents
      data.azurerm_subnet.infraci_jenkins_io_kubernetes_agent_sponsorship.id,  # infra.ci (Terraform management) container agents
    ]
    bypass = ["Metrics", "Logging", "AzureServices"]
  }
}

# GeoIP data persist
resource "azurerm_storage_share" "geoip_data" {
  name                 = "geoip-data"
  storage_account_name = azurerm_storage_account.publick8s.name
  quota                = 1 # GeoIP databses weight around 80Mb
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
