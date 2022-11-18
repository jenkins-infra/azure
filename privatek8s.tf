data "azurerm_subscription" "jenkins" {
}

resource "azurerm_resource_group" "privatek8s" {
  name     = "privatek8s"
  location = var.location
  tags     = local.default_tags
}

resource "random_pet" "suffix_privatek8s" {
  # You want to taint this resource in order to get a new pet
}

# Important: the Enterprise Application "terraform-production" used by this repo pipeline needs to be able to manage this subnet
# See the corresponding role assignment for this cluster added here (private repo):
# https://github.com/jenkins-infra/terraform-states/blob/1f44cdb8c6837021b1007fef383207703b0f4d76/azure/main.tf#L49
resource "azurerm_subnet" "privatek8s_tier" {
  name                 = "privatek8s-tier"
  resource_group_name  = data.azurerm_resource_group.private_prod.name
  virtual_network_name = data.azurerm_virtual_network.private_prod.name
  address_prefixes     = ["10.242.0.0/16"]
}

#tfsec:ignore:azure-container-logging #tfsec:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "privatek8s" {
  name                              = "privatek8s-${random_pet.suffix_privatek8s.id}"
  location                          = azurerm_resource_group.privatek8s.location
  resource_group_name               = azurerm_resource_group.privatek8s.name
  kubernetes_version                = var.kubernetes_version
  dns_prefix                        = "privatek8s-${random_pet.suffix_privatek8s.id}"
  role_based_access_control_enabled = true # default value, added to please tfsec
  # api_server_authorized_ip_ranges   = ["176.185.227.180/32"] # TODO: set correct value

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    ## https://learn.microsoft.com/en-gb/azure/aks/configure-kubenet-dual-stack
    # ip_versions = ["IPv4", "IPv6"]
  }

  default_node_pool {
    name            = "systempool"
    vm_size         = "Standard_D2as_v4"
    os_disk_type    = "Ephemeral"
    os_disk_size_gb = 30
    node_count      = 1
    vnet_subnet_id  = azurerm_subnet.privatek8s_tier.id
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
  vnet_subnet_id        = azurerm_subnet.privatek8s_tier.id
  tags                  = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "infracipool" {
  name                  = "infracipool"
  vm_size               = "Standard_D4s_v3"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 30
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s.id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 2
  zones                 = [3]
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

resource "azurerm_role_assignment" "privatek8s_networkcontributor" {
  scope                            = "${data.azurerm_subscription.jenkins.id}/resourceGroups/${data.azurerm_resource_group.private_prod.name}/providers/Microsoft.Network/virtualNetworks/${data.azurerm_virtual_network.private_prod.name}/subnets/${azurerm_subnet.privatek8s_tier.name}" # azurerm_subnet.privatek8s_tier.name
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
  skip_service_principal_aad_check = true
}

output "privatek8s_kube_config" {
  value     = azurerm_kubernetes_cluster.privatek8s.kube_config_raw
  sensitive = true
}

output "privatek8s_public_ip_address" {
  value = azurerm_public_ip.public_privatek8s.ip_address
}
