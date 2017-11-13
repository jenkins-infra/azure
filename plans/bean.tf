# This cluster is a bigger and will replace pea cluster

resource "azurerm_resource_group" "bean" {
  name     = "${var.prefix}bean"
  location = "${var.location}"
  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "bean" {
    name                     = "${azurerm_resource_group.bean.name}"
    resource_group_name      = "${azurerm_resource_group.bean.name}"
    location                 = "${var.location}"
    account_tier             = "Standard"
    account_replication_type = "GRS"
    depends_on               = ["azurerm_resource_group.bean"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_container_service" "bean" {
  depends_on             = ["azurerm_resource_group.bean"]
  name                   = "${azurerm_resource_group.bean.name}"
  location               = "${azurerm_resource_group.bean.location}"
  resource_group_name    = "${azurerm_resource_group.bean.name}"
  orchestration_platform = "Kubernetes"

  master_profile {
    count      = 3
    dns_prefix = "${azurerm_resource_group.bean.name}"
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = "${file("${var.ssh_pubkey_path}")}"
    }
  }

  agent_pool_profile {
    name       = "bean"
    count      = 5
    dns_prefix = "agent${azurerm_resource_group.bean.name}"
    vm_size    = "Standard_DS4_v2"
  }

  service_principal {
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
  }

  diagnostics_profile {
    enabled = false
  }

  tags {
    env = "${var.prefix}"
  }
}
