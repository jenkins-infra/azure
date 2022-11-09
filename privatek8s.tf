resource "azurerm_resource_group" "privatek8s" {
  name     = "privatek8s"
  location = "East US 2"
}

resource "random_pet" "suffix_privatek8s" {
  # You want to taint this resource in order to get a new pet
}

resource "azurerm_subnet" "privatek8s_tier" {
  name                 = "privatek8s-tier"
  resource_group_name  = data.azurerm_resource_group.private_prod.name
  virtual_network_name = data.azurerm_virtual_network.private_prod.name
  address_prefixes     = ["10.242.0.0/16"]
}

#tfsec:ignore:azure-container-logging
resource "azurerm_kubernetes_cluster" "privatek8s" {
  name                = "privatek8s-${random_pet.suffix_privatek8s.id}"
  location            = azurerm_resource_group.privatek8s.location
  resource_group_name = azurerm_resource_group.privatek8s.name
  # Kubernetes version in format '<MINOR>.<MINOR>'
  kubernetes_version                = "1.23"
  dns_prefix                        = "privatek8s-${random_pet.suffix_privatek8s.id}"
  role_based_access_control_enabled = true           # default value, added to please tfsec
  api_server_authorized_ip_ranges   = ["0.0.0.0/32"] # TODO: set correct value
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  default_node_pool {
    name           = "systempool"
    node_count     = 1
    vm_size        = "Standard_D2as_v4"
    vnet_subnet_id = azurerm_subnet.privatek8s_tier.id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "linuxpool" {
  name                  = "linuxpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  vm_size               = "Standard_D4s_v3"
  vnet_subnet_id        = azurerm_subnet.privatek8s_tier.id
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 3

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "infracipool" {
  name                  = "infracipool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  vm_size               = "Standard_D4s_v3"
  vnet_subnet_id        = azurerm_subnet.privatek8s_tier.id
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 2

  # Spot instances
  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = "-1" # in $, -1 = On demand pricing
  # Note: label and taint added automatically when in "Spot" priority, putting it here to explicit them
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = local.default_tags
}

# one public IP for cluster load balancer
# one record (data to existing dns zone)
# one public IP for gateway (?)
# public IP external requests count is limited

# definition of storage classes with correct CSI type (with helmfile provider)

output "privatek8s_client_certificate" {
  value     = azurerm_kubernetes_cluster.privatek8s.kube_config.0.client_certificate
  sensitive = true
}

output "privatek8s_kube_config" {
  value     = azurerm_kubernetes_cluster.privatek8s.kube_config_raw
  sensitive = true
}
