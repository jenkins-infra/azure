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

resource "azurerm_dns_a_record" "private_publick8s" {
  name                = "private.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = ["10.245.2.12"] # External IP of the private-nginx ingress LoadBalancer, created by https://github.com/jenkins-infra/kubernetes-management/blob/54a0d4aa72b15f4236abcfbde00a080905bbb890/clusters/publick8s.yaml#L63-L69
  tags                = local.default_tags
}

resource "azurerm_kubernetes_cluster" "publick8s" {
  name     = local.aks_clusters["publick8s"].name
  location = azurerm_resource_group.publick8s.location
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true

  resource_group_name               = azurerm_resource_group.publick8s.name
  kubernetes_version                = local.aks_clusters["publick8s"].kubernetes_version
  dns_prefix                        = local.aks_clusters["publick8s"].name
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

  node_provisioning_profile {
    default_node_pools = "Auto"
  }

  default_node_pool {
    name                         = "linuxpool"
    temporary_name_for_rotation  = "tempsystem"
    only_critical_addons_enabled = true # We run our workloads along the system workloads
    vm_size                      = "Standard_D2pds_v5"
    upgrade_settings {
      drain_timeout_in_minutes = 5 # If a pod cannot be evicted in less than 5 min, then upgrades fails
      max_surge                = 1 # Upgrade node one by one to avoid services to go down (when only 2 replicas)
    }
    os_sku               = "AzureLinux"
    kubelet_disk_type    = "OS"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 75 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dpdsv5-series?tabs=sizestoragelocal
    orchestrator_version = local.aks_clusters["publick8s"].kubernetes_version
    auto_scaling_enabled = true
    min_count            = 2
    max_count            = 5
    vnet_subnet_id       = data.azurerm_subnet.publick8s.id
    tags                 = local.default_tags
    zones                = [1, 2, 3]
    # No custom node_taints
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "publick8s_linuxapps" {
  name    = "linuxapps" # 12 char. max on Linux, only letters and numbers
  vm_size = "Standard_D4pds_v5"

  upgrade_settings {
    drain_timeout_in_minutes = 5 # If a pod cannot be evicted in less than 5 min, then upgrades fails
    max_surge                = 1 # Upgrade node one by one to avoid services to go down (when only 2 replicas)
  }
  os_disk_type          = "Ephemeral"
  kubelet_disk_type     = "OS"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dpdsv5-series?tabs=sizestoragelocal
  orchestrator_version  = local.aks_clusters["publick8s"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  auto_scaling_enabled  = true
  min_count             = 2
  max_count             = 5
  zones                 = [1, 2, 3]
  vnet_subnet_id        = data.azurerm_subnet.publick8s.id
  # No custom node_taints

  lifecycle {
    ignore_changes = [node_count]
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
resource "azurerm_public_ip" "publick8s_ips" {
  for_each = local.aks_clusters.publick8s.public_ips

  name                = each.key
  resource_group_name = azurerm_resource_group.prod_public_ips.name
  location            = var.location
  ip_version          = each.value
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "publick8s_ips" {
  for_each = local.aks_clusters.publick8s.public_ips

  name       = each.key
  scope      = azurerm_public_ip.publick8s_ips[each.key].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when publick8s cluster is re-created"
}
resource "azurerm_role_assignment" "publick8s_ips_networkcontributor" {
  for_each = local.aks_clusters.publick8s.public_ips

  scope                            = azurerm_public_ip.publick8s_ips[each.key].id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
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
  for_each = var.environment == "staging" ? toset([]) : toset(concat(flatten(azurerm_kubernetes_cluster.publick8s.network_profile[*].load_balancer_profile[*].effective_outbound_ips)))

  name                = element(split("/", each.key), "-1")
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
}

# Allow access to the private Azure Container Registry through an Azure Endpoint NIC
module "publick8s_acr_pe" {
  source = "./modules/azure-container-registry-private-links"

  providers = {
    azurerm     = azurerm
    azurerm.acr = azurerm
  }

  name = "publick8s"

  acr_name     = azurerm_container_registry.dockerhub_mirror.name
  acr_location = azurerm_container_registry.dockerhub_mirror.location
  acr_rg_name  = azurerm_container_registry.dockerhub_mirror.resource_group_name

  subnet_name  = data.azurerm_subnet.publick8s.name
  vnet_name    = data.azurerm_virtual_network.public.name
  vnet_rg_name = data.azurerm_virtual_network.public.resource_group_name

  default_tags = local.default_tags
}
