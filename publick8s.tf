resource "azurerm_resource_group" "publick8s" {
  name     = "publick8s"
  location = var.location
  tags     = local.default_tags
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

resource "azurerm_dns_a_record" "public_publick8s" {
  name                = "public.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.old_publick8s_ipv4.ip_address] # TODO: switch to the new cluster IP
  tags                = local.default_tags
}

resource "azurerm_dns_aaaa_record" "public_publick8s" {
  name                = "public.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.old_publick8s_ipv6.ip_address] # TODO: switch to the new cluster IP
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

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "new_publick8s" {
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
    min_count            = 1
    max_count            = 5
    vnet_subnet_id       = data.azurerm_subnet.publick8s_tier.id
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
    data.azurerm_subnet.publick8s_tier.id,        # Node pool
    data.azurerm_subnet.public_vnet_data_tier.id, # Private LB and Private endpoints
  ])
  scope                            = each.key
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.new_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to join NAT gateway. Required to manage Azure PLS through Kubernetes Services until old subnets are associated with the NAT gateway.
# TODO: uncomment if needed when creating the Kubernetes Service of type PLS
# resource "azurerm_role_definition" "publick8s_outbound_gateway" {
#   name  = "publick8s_outbount_gateway"
#   scope = data.azurerm_nat_gateway.publick8s_outbound.id
#   permissions {
#     actions = ["Microsoft.Network/natGateways/join/action"]
#   }
# }
# resource "azurerm_role_assignment" "publick8s_nat_gateway" {
#   scope                            = data.azurerm_nat_gateway.publick8s_outbound.id
#   role_definition_id               = azurerm_role_definition.publick8s_outbound_gateway.role_definition_resource_id
#   principal_id                     = azurerm_kubernetes_cluster.new_publick8s.identity[0].principal_id
#   skip_service_principal_aad_check = true
# }
## End TODO remove

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
  principal_id                     = azurerm_kubernetes_cluster.new_publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}
## Kubernetes Resources
