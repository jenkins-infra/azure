resource "azurerm_resource_group" "maink8s" {
  name     = "${var.prefix}maink8s"
  location = "${var.location}"
  tags {
    environment = "${var.prefix}"
  }
}

# Azure LogAnalytics to visualize Kubernetes logs
resource "azurerm_log_analytics_workspace" "maink8s" {
  name                = "${var.prefix}maink8s"
  location            = "${azurerm_resource_group.maink8s.location}"
  resource_group_name = "${azurerm_resource_group.maink8s.name}"
  sku                 = "Standard"
  retention_in_days   = 30
}

# Public IP used by Default ingress resource on Kubernetes cluster
resource "azurerm_public_ip" "maink8s" {
  name                         = "${var.prefix}nginx-maink8s"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.maink8s.name}"
  public_ip_address_allocation = "Static"
  idle_timeout_in_minutes      = 30
  tags {
    environment = "${var.prefix}"
  }
}

# Public IP used for ldap on Kubernetes cluster
resource "azurerm_public_ip" "maink8sldap" {
  name                         = "${var.prefix}ldap"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.maink8s.name}"
  public_ip_address_allocation = "Static"
  idle_timeout_in_minutes      = 30
  tags {
    environment = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "maink8s" {
    name                     = "${azurerm_resource_group.maink8s.name}"
    resource_group_name      = "${azurerm_resource_group.maink8s.name}"
    location                 = "${var.location}"
    account_tier             = "Standard"
    account_replication_type = "GRS"
    depends_on               = ["azurerm_resource_group.maink8s"]
    tags {
        environment = "${var.prefix}"
    }
}

resource "azurerm_kubernetes_cluster" "maink8s" {
  depends_on             = ["azurerm_subnet.public_app"]
  name                   = "${azurerm_resource_group.maink8s.name}"
  location               = "${azurerm_resource_group.maink8s.location}"
  dns_prefix             = "${var.prefix}"
  resource_group_name    = "${azurerm_resource_group.maink8s.name}"
  kubernetes_version     = "1.11.2"

  agent_pool_profile {
    name    = "maink8spool"
    count   = "3"
    vm_size = "Standard_DS4_v2"
    os_type = "Linux"
    vnet_subnet_id = "${azurerm_subnet.public_k8s.id}" # ! Only one AKS per subnet
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = "${file("${var.ssh_pubkey_path}")}"
    }
  }

  network_profile {
    network_plugin     = "kubenet"
    service_cidr       = "10.128.0.0/16" # Number of IPs needed  = (number of nodes) + (number of nodes * pods per node)
    dns_service_ip     = "10.128.0.10" # Must be in service_cidr range
    docker_bridge_cidr = "172.17.0.1/16"
  }

  addon_profile {
    oms_agent {
      enabled = "true"
      log_analytics_workspace_id = "${ azurerm_log_analytics_workspace.maink8s.id }"
    }
  }

  service_principal {
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
  }

  tags {
    environment = "${var.prefix}"
    location    = "${azurerm_resource_group.maink8s.location}"
  }
}
