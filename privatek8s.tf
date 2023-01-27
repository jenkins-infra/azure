data "azurerm_subscription" "jenkins" {
}

resource "azurerm_resource_group" "privatek8s" {
  name     = "prod-privatek8s"
  location = var.location
  tags     = local.default_tags
}

resource "random_pet" "suffix_privatek8s" {
  # You want to taint this resource in order to get a new pet
}

# Important: the Enterprise Application "terraform-production" used by this repo pipeline needs to be able to manage this subnet
# See the corresponding role assignment for this cluster added here (private repo):
# https://github.com/jenkins-infra/terraform-states/blob/1f44cdb8c6837021b1007fef383207703b0f4d76/azure/main.tf#L49
data "azurerm_subnet" "privatek8s_tier" {
  name                 = "privatek8s-tier"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}

#tfsec:ignore:azure-container-logging #tfsec:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "privatek8s" {
  name                              = "privatek8s-${random_pet.suffix_privatek8s.id}"
  location                          = azurerm_resource_group.privatek8s.location
  resource_group_name               = azurerm_resource_group.privatek8s.name
  kubernetes_version                = "1.23.12"
  dns_prefix                        = "privatek8s-${random_pet.suffix_privatek8s.id}"
  role_based_access_control_enabled = true # default value, added to please tfsec

  api_server_access_profile {
    authorized_ip_ranges = setunion(
      formatlist("%s/32", values(local.admin_allowed_ips)),
      data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
    )
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  default_node_pool {
    name            = "systempool"
    vm_size         = "Standard_D2as_v4"
    os_disk_type    = "Ephemeral"
    os_disk_size_gb = 30
    node_count      = 1
    vnet_subnet_id  = data.azurerm_subnet.privatek8s_tier.id
    tags            = local.default_tags
    zones           = [3]
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "linuxpool" {
  name                  = "linuxpool"
  vm_size               = "Standard_D4s_v3"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 30
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 3
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_tier.id
  tags                  = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "infracipool" {
  name                  = "infracipool"
  vm_size               = "Standard_D8s_v3"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 30
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 20
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_tier.id

  # Spot instances
  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = "-1" # in $, -1 = On demand pricing
  # Note: label and taint added automatically when in "Spot" priority, putting it here to explicit them
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  node_taints = [
    "jenkins=infra.ci.jenkins.io:NoSchedule",
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule",
  ]

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "highmempool" {
  name                  = "highmemlinux"
  vm_size               = "Standard_D8s_v3"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 100
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 3
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_tier.id
  node_taints = [
    "os=linux:NoSchedule",
    "profile=highmem:NoSchedule",
  ]

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "windowspool" {
  name                  = "win"
  vm_size               = "Standard_D4s_v3"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 100
  os_type               = "Windows"
  os_sku                = "Windows2019"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 3
  zones                 = [3]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_tier.id
  node_taints = [
    "os=windows:NoSchedule",
  ]

  tags = local.default_tags
}

# Allow cluster to manage LBs in the privatek8s-tier subnet (Public LB)
resource "azurerm_role_assignment" "privatek8s_networkcontributor" {
  scope                            = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private.name}/subnets/${data.azurerm_subnet.privatek8s_tier.name}"
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage LBs in the data-tier subnet (internal LBs)
resource "azurerm_role_assignment" "datatier_networkcontributor" {
  scope                            = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private.name}/subnets/${data.azurerm_subnet.private_vnet_data_tier.name}"
  role_definition_name             = "Network Contributor"
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

# Used later by the load balancer deployed on the cluster, see https://github.com/jenkins-infra/kubernetes-management/config/privatek8s.yaml
resource "azurerm_public_ip" "public_privatek8s" {
  name                = "public-privatek8s"
  resource_group_name = azurerm_kubernetes_cluster.privatek8s.node_resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "public_privatek8s" {
  name                = "public.privatek8s"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.public_privatek8s.ip_address]
  tags                = local.default_tags
}

output "privatek8s_kube_config" {
  value     = azurerm_kubernetes_cluster.privatek8s.kube_config_raw
  sensitive = true
}

output "privatek8s_public_ip_address" {
  value = azurerm_public_ip.public_privatek8s.ip_address
}

output "privatek8s_kube_config_command" {
  value = "az aks get-credentials --name ${azurerm_kubernetes_cluster.privatek8s.name} --resource-group ${azurerm_kubernetes_cluster.privatek8s.resource_group_name}"
}
