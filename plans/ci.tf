#
# Resources related to our CI infrastructure for ci.jenkins.io or trusted.ci
#


resource "azurerm_resource_group" "ci" {
    name     = "${var.prefix}jenkinsci"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "ci_storage" {
    name                     = "${var.prefix}jenkinscistore"
    resource_group_name      = "${azurerm_resource_group.ci.name}"
    location                 = "${var.location}"
    account_tier             = "Standard"
    account_replication_type = "LRS"

    tags {
        environment = "${var.prefix}"
    }
}

resource "azurerm_storage_container" "ci_container" {
    name                  = "vhds"
    resource_group_name   = "${azurerm_resource_group.ci.name}"
    storage_account_name  = "${azurerm_storage_account.ci_storage.name}"
    container_access_type = "private"
}

resource "azurerm_public_ip" "ci_trusted_agent_1" {
    name                         = "trusted-agent-1"
    location                     = "${azurerm_resource_group.ci.location}"
    resource_group_name          = "${azurerm_resource_group.ci.name}"
    public_ip_address_allocation = "dynamic"

    tags {
        environment = "${var.prefix}"
    }
}

resource "azurerm_network_interface" "ci_trusted_agent_1_nic" {
    name                = "trusted-agent-1-nic"
    location            = "${var.location}"
    resource_group_name = "${azurerm_resource_group.ci.name}"

    ip_configuration {
        name                          = "testconfiguration1"
        subnet_id                     = "${azurerm_subnet.public_dmz.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id          = "${azurerm_public_ip.ci_trusted_agent_1.id}"
    }
}

resource "azurerm_virtual_machine" "ci_trusted_agent_1" {
    name                  = "trusted-agent-1"
    location              = "${var.location}"
    resource_group_name   = "${azurerm_resource_group.ci.name}"
    network_interface_ids = ["${azurerm_network_interface.ci_trusted_agent_1_nic.id}"]
    vm_size               = "Standard_DS4_v2"

    delete_os_disk_on_termination = true
    delete_data_disks_on_termination = true

    storage_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }

    storage_os_disk {
        name          = "trusted-agent-1-disk"
        vhd_uri       = "${azurerm_storage_account.ci_storage.primary_blob_endpoint}${azurerm_storage_container.ci_container.name}/trustedagent1os.vhd"
        caching       = "ReadWrite"
        create_option = "FromImage"
    }


    os_profile {
        computer_name  = "trusted-agent-1"
        admin_username = "azureuser"
        admin_password = "${random_id.prefix.hex}"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys = [
            {
                path = "/home/azureuser/.ssh/authorized_keys"
                key_data = "${file("${var.ssh_pubkey_path}")}"
            },
        ]
    }

    tags {
        environment = "${var.prefix}"
    }
}


resource "random_id" "prefix" {
    keepers {
        prefix = "${var.prefix}"
    }
    byte_length = 16
}
