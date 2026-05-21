########################################################################################################
# Resources in other Resource Groups ("RG") in the CDF subscription
# which lifecycle are not bound directly to the cluster and its RG.
########################################################################################################

# Used later by the load balancer deployed on the cluster
# Use case is to allow incoming webhooks
resource "azurerm_public_ip" "privatek8s_sponsored_public" {
  name                = "public-privatek8s-sponsored"
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "privatek8s_sponsored_public" {
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
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.privatek8s_sponsored_app.id
    tags                 = local.default_tags
    zones                = [1, 2] # Many zones to ensure it is always able to provide machines in the region. Note: Zone 3 is not allowed for system pool.
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
  zones                 = [1, 2]
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
  zones                 = [2, 3]
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
  zones                 = [2, 3]
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
  zones                 = [1, 2]
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
  vm_size  = "Standard_D4ads_v7"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 220 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv7-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["privatek8s-sponsored"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsored.id
  os_type               = "Windows"
  os_sku                = "Windows2022"
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [1, 2]
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

  ])
  scope                            = each.key
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsored.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage the public IP privatek8s-sponsored
# It is used for managing the public IP of the LB of the public ingress controller
resource "azurerm_role_assignment" "privatek8s_sponsored_publicip_networkcontributor" {
  provider                         = azurerm.jenkins-sponsored
  scope                            = azurerm_public_ip.privatek8s_sponsored_public.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsored.identity[0].principal_id
  skip_service_principal_aad_check = true
}
