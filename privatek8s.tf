resource "azurerm_resource_group" "privatek8s" {
  name     = "privatek8s"
  location = var.location
  tags     = local.default_tags
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

# Automatic upgrades for patch versions
# Note: The first time we apply this configuration, Terraform will apply whatever latest version it finds in the AKS versions data source.
# When new versions are available, AKS will upgrade automatically. But Azure will not allow skip-version upgrades.
# You may need to pin your data source to the next version, upgrade, then remove the pinning and upgrade again to get to the latest version.
data "azurerm_kubernetes_service_versions" "current" {
  location       = var.location
  version_prefix = "1.23"
}

#tfsec:ignore:azure-container-logging
resource "azurerm_kubernetes_cluster" "privatek8s" {
  name                              = "privatek8s-${random_pet.suffix_privatek8s.id}"
  location                          = azurerm_resource_group.privatek8s.location
  resource_group_name               = azurerm_resource_group.privatek8s.name
  node_resource_group               = "${azurerm_resource_group.privatek8s.name}-aks"
  kubernetes_version                = data.azurerm_kubernetes_service_versions.current.latest_version
  dns_prefix                        = "privatek8s-${random_pet.suffix_privatek8s.id}"
  role_based_access_control_enabled = true                                 # default value, added to please tfsec
  api_server_authorized_ip_ranges   = ["0.0.0.0/32", "176.185.227.180/32"] # TODO: set correct value
  # public_network_access_enabled     = true # default value, 'no changes.'
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  default_node_pool {
    name                 = "systempool"
    vm_size              = "Standard_D2as_v4"
    orchestrator_version = data.azurerm_kubernetes_service_versions.current.latest_version
    node_count           = 1
    vnet_subnet_id       = azurerm_subnet.privatek8s_tier.id
    tags                 = local.default_tags
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "linuxpool" {
  name                  = "linuxpool"
  vm_size               = "Standard_D4s_v3"
  orchestrator_version  = data.azurerm_kubernetes_service_versions.current.latest_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 3
  zones                 = [1, 2, 3]
  vnet_subnet_id        = azurerm_subnet.privatek8s_tier.id
  tags                  = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "infracipool" {
  name                  = "infracipool"
  vm_size               = "Standard_D4s_v3"
  orchestrator_version  = data.azurerm_kubernetes_service_versions.current.latest_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 2
  zones                 = [1, 2, 3]
  vnet_subnet_id        = azurerm_subnet.privatek8s_tier.id

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

resource "azurerm_public_ip" "public_privatek8s" {
  name                = "public-privatek8s"
  resource_group_name = "${azurerm_resource_group.privatek8s.name}-aks"
  location            = var.location
  allocation_method   = "Static"
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

output "privatek8s_public_ip_address" {
  value = azurerm_public_ip.public_privatek8s.ip_address
}
