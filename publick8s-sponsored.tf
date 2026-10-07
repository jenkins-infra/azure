resource "azurerm_resource_group" "publick8s_sponsored" {
  provider = azurerm.jenkins-sponsored

  name     = "publick8s-sponsored"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_dns_a_record" "public_publick8_sponsored" {
  name                = "public.publick8s_sponsored"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_public_ip.publick8s_sponsored_ips["temp-publick8s-public-ipv4"].ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_aaaa_record" "public_publick8s_sponsored" {
  name                = "public.publick8s_sponsored"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_public_ip.publick8s_sponsored_ips["temp-publick8s-public-ipv6"].ip_address]
  tags                = local.default_tags
}

# TODO: uncomment when private-nginx-ingress has been deployed on publick8s-sponsored
# resource "azurerm_dns_a_record" "private_publick8s_sponsored" {
#   name                = "private.publick8s_sponsored"
#   zone_name           = data.azurerm_dns_zone.jenkinsio.name
#   resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
#   ttl                 = 60
#   records             = ["????"] # External IP of the private-nginx ingress LoadBalancer, created by https://github.com/jenkins-infra/kubernetes-management/???
#   tags                = local.default_tags
# }

resource "azurerm_kubernetes_cluster" "publick8s_sponsored" {
  provider = azurerm.jenkins-sponsored

  name     = local.aks_clusters["publick8s_sponsored"].name
  location = azurerm_resource_group.publick8s_sponsored.location
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true

  resource_group_name               = azurerm_resource_group.publick8s_sponsored.name
  kubernetes_version                = local.aks_clusters["publick8s_sponsored"].kubernetes_version
  dns_prefix                        = local.aks_clusters["publick8s_sponsored"].name
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidrs           = local.aks_clusters["publick8s_sponsored"].pod_cidrs # Plural form: dual stack ipv4/ipv6
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

  node_provisioning_profile {
    default_node_pools = "Auto"
  }

  default_node_pool {
    name                         = "linuxpool"
    temporary_name_for_rotation  = "tempsystem"
    only_critical_addons_enabled = true # We run our workloads along the system workloads
    vm_size                      = "Standard_D2pds_v6"
    upgrade_settings {
      drain_timeout_in_minutes = 5 # If a pod cannot be evicted in less than 5 min, then upgrades fails
      max_surge                = 1 # Upgrade node one by one to avoid services to go down (when only 2 replicas)
    }
    os_sku               = "AzureLinux"
    kubelet_disk_type    = "OS"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 110 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dpdsv6-series?tabs=sizestoragelocal
    orchestrator_version = local.aks_clusters["publick8s_sponsored"].kubernetes_version
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = 5
    vnet_subnet_id       = data.azurerm_subnet.publick8s_sponsored.id
    tags                 = local.default_tags
    zones                = [1, 2]
    # No custom node_taints
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "publick8s_sponsored_linuxapps" {
  provider = azurerm.jenkins-sponsored

  name    = "linuxapps" # 12 char. max on Linux, only letters and numbers
  vm_size = "Standard_D4pds_v6"

  upgrade_settings {
    drain_timeout_in_minutes = 5 # If a pod cannot be evicted in less than 5 min, then upgrades fails
    max_surge                = 1 # Upgrade node one by one to avoid services to go down (when only 2 replicas)
  }
  os_disk_type          = "Ephemeral"
  kubelet_disk_type     = "OS"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 220 # https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dpdsv6-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["publick8s_sponsored"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s_sponsored.id
  auto_scaling_enabled  = true
  min_count             = 2
  max_count             = 5
  zones                 = [1, 2]
  vnet_subnet_id        = data.azurerm_subnet.publick8s_sponsored.id
  # No custom node_taints

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Allow cluster to manage network resources in the associated subnets
# It is used for managing LBs of the public and private ingress controllers
resource "azurerm_role_assignment" "publick8s_sponsored_subnets_networkcontributor" {
  provider = azurerm.jenkins-sponsored

  for_each = toset([
    data.azurerm_subnet.publick8s_sponsored.id, # Node pool
  ])
  scope                            = each.key
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s_sponsored.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Each public load balancer used by this cluster is setup with a locked public IP.
# Using a pre-determined public IP eases DNS setup and changes, but requires cluster to have the "Network Contributor" role on the IP.
resource "azurerm_public_ip" "publick8s_sponsored_ips" {
  provider = azurerm.jenkins-sponsored

  for_each = local.aks_clusters.publick8s_sponsored.public_ips

  name                = each.key
  resource_group_name = azurerm_resource_group.prod_publick8s_ips_sponsored.name
  location            = var.location
  ip_version          = each.value
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}

# TODO: uncomment when final IPs are ready
# resource "azurerm_management_lock" "publick8s_sponsored_ips" {
#  provider = azurerm.jenkins-sponsored
#
#   for_each = local.aks_clusters.publick8s_sponsored.public_ips
#
#   name       = each.key
#   scope      = azurerm_public_ip.publick8s_sponsored_ips[each.key].id
#   lock_level = "CanNotDelete"
#   notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
# }

resource "azurerm_role_assignment" "publick8s_sponsored_ips_networkcontributor" {
  provider = azurerm.jenkins-sponsored

  for_each = local.aks_clusters.publick8s_sponsored.public_ips

  scope                            = azurerm_public_ip.publick8s_sponsored_ips[each.key].id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s_sponsored.identity[0].principal_id
  skip_service_principal_aad_check = true
}
