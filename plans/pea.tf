resource "azurerm_resource_group" "pea" {
  name     = "${var.prefix}pea"
  location = "${var.location}"
  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "pea" {
    name                = "${azurerm_resource_group.pea.name}"
    resource_group_name = "${azurerm_resource_group.pea.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
    depends_on          = ["azurerm_resource_group.pea"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_container_service" "pea" {
  depends_on             = ["azurerm_resource_group.pea"]
  name                   = "${azurerm_resource_group.pea.name}"
  location               = "${azurerm_resource_group.pea.location}"
  resource_group_name    = "${azurerm_resource_group.pea.name}"
  orchestration_platform = "Kubernetes"

  master_profile {
    count      = 3
    dns_prefix = "${azurerm_resource_group.pea.name}"
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = "${file("${var.ssh_pubkey_path}")}"
    }
  }

  agent_pool_profile {
    name       = "pea"
    count      = 3
    dns_prefix = "agent${azurerm_resource_group.pea.name}"
    vm_size    = "${var.k8s_agent_size}"
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
