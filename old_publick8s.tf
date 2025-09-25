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

resource "azurerm_dns_a_record" "public_old_publick8s" {
  name                = "public.${local.aks_clusters["old_publick8s"].name}"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_public_ip.old_publick8s_ipv4.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_aaaa_record" "public_old_publick8s" {
  name                = "public.${local.aks_clusters["old_publick8s"].name}"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_public_ip.old_publick8s_ipv6.ip_address]
  tags                = local.default_tags
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
resource "azurerm_public_ip" "old_publick8s_ipv6" {
  name                = "public-publick8s-ipv6"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = "IPv6"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
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


## TODO: remove the resources below
resource "azurerm_resource_group" "ldap" {
  name     = "ldap"
  location = var.location
  tags     = local.default_tags
}

## LDAP uses the following data disk for its `/var/lib/ldap` data directory
resource "azurerm_managed_disk" "ldap_jenkins_io_data_old" {
  name                = "ldap-jenkins-io-data"
  location            = azurerm_resource_group.ldap.location
  resource_group_name = azurerm_resource_group.ldap.name
  # ZRS to ensure we can move service across AZs
  # Standard because it is enough for LDAP's IOPS and I/O bandwidth
  # Ref. https://azure.microsoft.com/en-us/pricing/details/managed-disks/
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  # LDAP data set is between 300 and 500 Mb
  # Class E1 (4G) only allow 7800 paid transactions per hour, while LDAP may peak at 8500 sometimes so E2 it is
  # Ref. https://azure.microsoft.com/en-us/pricing/details/managed-disks/
  disk_size_gb = 8
  tags         = local.default_tags
}


## LDAP is backed-up (at regular intervals and on stopping) by a side container into the following Azure file storage
resource "azurerm_storage_account" "ldap_backups" {
  name                     = "ldapjenkinsiobackups"
  resource_group_name      = azurerm_resource_group.ldap.name
  location                 = azurerm_resource_group.ldap.location
  account_tier             = "Standard"
  account_replication_type = "GRS" # recommended for backups
  # https://learn.microsoft.com/en-gb/azure/storage/common/infrastructure-encryption-enable
  infrastructure_encryption_enabled = true
  min_tls_version                   = "TLS1_2" # default value, needed for tfsec

  tags = local.default_tags
}
resource "azurerm_storage_account_network_rules" "ldap_access" {
  storage_account_id = azurerm_storage_account.ldap_backups.id

  default_action = "Deny"
  virtual_network_subnet_ids = concat(
    [
      # Mounting share in the publick8s AKS cluster
      data.azurerm_subnet.publick8s_tier.id,
      data.azurerm_subnet.publick8s.id,
    ],
    # Required for managing the resource
    local.app_subnets["infra.ci.jenkins.io"].agents,
  )
  bypass = ["Metrics", "Logging", "AzureServices"]
}
resource "azurerm_storage_share" "ldap" {
  name               = "ldap"
  storage_account_id = azurerm_storage_account.ldap_backups.id
  # Unless this is a Premium Storage, we only pay for the storage we consume. Let's use existing quota.
  quota = 5120 # 5To
}
