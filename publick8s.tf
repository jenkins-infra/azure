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

#tfsec:ignore:azure-container-logging #tfsec:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "publick8s" {
  name                              = "publick8s-${random_pet.suffix_publick8s.id}"
  location                          = azurerm_resource_group.publick8s.location
  resource_group_name               = azurerm_resource_group.publick8s.name
  kubernetes_version                = var.kubernetes_version
  dns_prefix                        = "publick8s-${random_pet.suffix_publick8s.id}"
  role_based_access_control_enabled = true # default value, added to please tfsec
  api_server_authorized_ip_ranges = setunion(
    values(local.admin_allowed_ips),
    data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
    # privatek8s nodes subnet
    data.azurerm_subnet.privatek8s_tier.address_prefixes,
    [local.privatek8s_pod_ip]
  )

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    ip_versions    = ["IPv4", "IPv6"]
  }

  default_node_pool {
    name            = "systempool"
    vm_size         = "Standard_D2as_v4"
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
  vm_size               = "Standard_D4s_v3"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 30
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 20
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

resource "kubernetes_storage_class" "managed_csi_premium_retain_public" {
  metadata {
    name = "managed-csi-premium-retain"
  }
  storage_provisioner = "disk.csi.azure.com"
  reclaim_policy      = "Retain"
  parameters = {
    skuname = "Premium_LRS"
  }
  provider = kubernetes.publick8s
}

# Used later by the load balancer deployed on the cluster, see https://github.com/jenkins-infra/kubernetes-management/config/publick8s.yaml
resource "azurerm_public_ip" "public_publick8s" {
  name                = "public-publick8s"
  resource_group_name = azurerm_kubernetes_cluster.publick8s.node_resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "public_publick8s" {
  name                = "public.publick8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.public_publick8s.ip_address]
  tags                = local.default_tags
}

output "publick8s_kube_config" {
  value     = azurerm_kubernetes_cluster.publick8s.kube_config_raw
  sensitive = true
}

output "publick8s_public_ip_address" {
  value = azurerm_public_ip.public_publick8s.ip_address
}

output "publick8s_kube_config_command" {
  value = "az aks get-credentials --name ${azurerm_kubernetes_cluster.publick8s.name} --resource-group ${azurerm_kubernetes_cluster.publick8s.resource_group_name}"
}
