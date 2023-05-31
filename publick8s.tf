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

#tfsec:ignore:azure-container-logging #tfsec:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "publick8s" {
  name                              = "publick8s-${random_pet.suffix_publick8s.id}"
  location                          = azurerm_resource_group.publick8s.location
  resource_group_name               = azurerm_resource_group.publick8s.name
  kubernetes_version                = "1.24.9"
  dns_prefix                        = "publick8s-${random_pet.suffix_publick8s.id}"
  role_based_access_control_enabled = true # default value, added to please tfsec
  api_server_access_profile {
    authorized_ip_ranges = setunion(
      # admins
      formatlist("%s/32", values(local.admin_allowed_ips)),
      # private VPN access
      data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
      # privatek8s nodes subnet
      data.azurerm_subnet.privatek8s_tier.address_prefixes,
      [local.privatek8s_outbound_ip_cidr],
    )
  }

  #tfsec:ignore:azure-container-configured-network-policy
  network_profile {
    network_plugin = "kubenet"
    ip_versions    = ["IPv4", "IPv6"]
  }

  default_node_pool {
    name            = "systempool"
    vm_size         = "Standard_D2as_v4" # 2 vCPU, 8 GB RAM, 16 GB disk, 4000 IOPS
    os_disk_type    = "Ephemeral"
    os_disk_size_gb = 30
    node_count      = 1
    vnet_subnet_id  = data.azurerm_subnet.publick8s_tier.id
    tags            = local.default_tags
    zones           = [3]
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "publicpool" {
  name                  = "publicpool"
  vm_size               = "Standard_D8s_v3" # 8 vCPU, 32 GB RAM, 64 GB disk, 16 000 IOPS
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 200 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 10
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.publick8s_tier.id
  tags                  = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "x86medium" {
  name                  = "x86medium"
  vm_size               = "Standard_D8s_v3" # 8 vCPU, 32 GB RAM, 64 GB disk, 16 000 IOPS
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 200 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dv3-dsv3-series#dsv3-series (depends on the instance size)
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 10
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.publick8s_tier.id
  tags                  = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "arm64medium" {
  name                  = "arm64medium"
  vm_size               = "Standard_D4pds_v5" # 4 vCPU, 16 GB RAM, local disk: 150 GB and 19000 IOPS
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/en-us/azure/virtual-machines/dpsv5-dpdsv5-series#dpdsv5-series (depends on the instance size)
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 10
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.publick8s_tier.id
  tags                  = local.default_tags
}

# Allow cluster to manage LBs in the publick8s-tier subnet (Public LB)
resource "azurerm_role_assignment" "publick8s_networkcontributor" {
  scope                            = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.public.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.public.name}/subnets/${data.azurerm_subnet.publick8s_tier.name}"
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.publick8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage LBs in the public-vnet-data-tier subnet (internal LBs)
resource "azurerm_role_assignment" "public_vnet_data_tier_networkcontributor" {
  scope                            = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.public.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.public.name}/subnets/${data.azurerm_subnet.public_vnet_data_tier.name}"
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

# Used later by the load balancer deployed on the cluster, see https://github.com/jenkins-infra/kubernetes-management/config/publick8s.yaml
resource "azurerm_public_ip" "publick8s_ipv4" {
  name                = "public-publick8s-ipv4"
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
  location            = var.location
  ip_version          = "IPv4"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}

resource "azurerm_public_ip" "publick8s_ipv6" {
  name                = "public-publick8s-ipv6"
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
  location            = var.location
  ip_version          = "IPv6"
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
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

output "publick8s_kube_config_command" {
  value = "az aks get-credentials --name ${azurerm_kubernetes_cluster.publick8s.name} --resource-group ${azurerm_kubernetes_cluster.publick8s.resource_group_name}"
}
