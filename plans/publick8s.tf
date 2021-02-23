variable "publick8s_windows_admin_password" {
  type    = string
  default = "2019082701"
}

resource "random_string" "publick8s_windows_admin_password" {
  length = 16

  keepers = {
    id = var.publick8s_windows_admin_password
  }
}

resource "azurerm_resource_group" "publick8s" {
  name     = "${var.prefix}publick8s"
  location = var.location

  tags = {
    environment = var.prefix
  }
}

# Azure LogAnalytics to visualize Kubernetes logs
resource "azurerm_log_analytics_workspace" "publick8s" {
  name                = "${var.prefix}publick8s"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.publick8s.name
  sku                 = "Standard"
  retention_in_days   = 30
}

resource "azurerm_storage_account" "publick8s" {
  name                     = azurerm_resource_group.publick8s.name
  resource_group_name      = azurerm_resource_group.publick8s.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  depends_on               = [azurerm_resource_group.publick8s]

  tags = {
    environment = var.prefix
  }
}

resource "azurerm_kubernetes_cluster" "publick8s" {
  depends_on          = [azurerm_subnet.publick8s]
  name                = azurerm_resource_group.publick8s.name
  location            = azurerm_resource_group.publick8s.location
  dns_prefix          = var.prefix
  resource_group_name = azurerm_resource_group.publick8s.name
  kubernetes_version  = "1.17.9" #az aks get-versions --location eastus --output table

  role_based_access_control {
    enabled = true
  }

  default_node_pool {
    name                = "linux"
    vm_size             = "Standard_D4s_v3"
    vnet_subnet_id      = azurerm_subnet.publick8s.id # ! Only one AKS per subnet
    os_disk_size_gb     = 100                         # It seems that terraform force a resource re-creation if size is not defined
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 8
    max_pods            = 200 # Private IPs pool for a node will be reserved at node creation
  }

  windows_profile {
    admin_username = "azureuser"
    admin_password = random_string.publick8s_windows_admin_password.result
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = file(var.ssh_pubkey_path)
    }
  }

  network_profile {
    network_plugin     = "azure"
    service_cidr       = "10.0.64.0/19" # Virtual IPs that Kubernetes assigns to internal services in your cluster.
    dns_service_ip     = "10.0.64.10"   # Must be in service_cidr range
    docker_bridge_cidr = "172.17.0.1/16"
  }

  addon_profile {
    oms_agent {
      enabled                    = "true"
      log_analytics_workspace_id = azurerm_log_analytics_workspace.publick8s.id
    }
  }

  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }

  tags = {
    environment = var.prefix
    location    = azurerm_resource_group.publick8s.location
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "highmem" {
  name                  = "highmemlinux"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  vm_size               = "Standard_D8s_v3"
  enable_auto_scaling   = true
  node_count            = 1
  max_pods              = 200

  node_taints = [
    "os=linux:NoSchedule",
    "profile=highmem:NoSchedule",
  ]

  os_disk_size_gb = 100
  os_type         = "Linux"
  vnet_subnet_id  = azurerm_subnet.publick8s.id

  min_count = 1
  max_count = 8
}

resource "azurerm_kubernetes_cluster_node_pool" "windows" {
  name                  = "win"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.publick8s.id
  vm_size               = "Standard_D4s_v3"
  enable_auto_scaling   = true
  node_count            = 1
  max_pods              = 200
  node_taints           = ["os=windows:NoSchedule"]
  os_disk_size_gb       = 200
  os_type               = "Windows"
  vnet_subnet_id        = azurerm_subnet.publick8s.id

  min_count = 1
  max_count = 3
}

resource "azurerm_role_assignment" "publick8s" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${azurerm_resource_group.publick8s.name}"
  role_definition_name = "Network Contributor"
  principal_id         = var.client_id
}

# Public IP used by the loadbalancer gw
resource "azurerm_public_ip" "publick8s" {
  depends_on              = [azurerm_kubernetes_cluster.publick8s]
  name                    = "${var.prefix}gw-publick8s"
  location                = var.location
  resource_group_name     = azurerm_resource_group.publick8s.name
  allocation_method       = "Static"
  idle_timeout_in_minutes = 30

  tags = {
    environment = var.prefix
  }
}

# Public IP used by loadbalancer gw for the new ingress controller
resource "azurerm_public_ip" "publick8s-2" {
  depends_on              = [azurerm_kubernetes_cluster.publick8s]
  name                    = "${var.prefix}gw-publick8s-2"
  location                = var.location
  resource_group_name     = azurerm_resource_group.publick8s.name
  allocation_method       = "Static"
  idle_timeout_in_minutes = 30

  tags = {
    environment = var.prefix
  }
}
