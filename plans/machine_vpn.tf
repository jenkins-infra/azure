# This terraform plan describe the virtual machine needed to run an openvpn service

resource "azurerm_resource_group" "vpn" {
  name     = "${var.prefix}vpn"
  location = "${var.location}"
  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_public_ip" "vpn" {
  name                         = "${var.prefix}vpn"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.vpn.name}"
  public_ip_address_allocation = "static"
  tags {
    environment = "${var.prefix}"
  }
}

# Interface within a network with ports 80,443 opened to the internet
resource "azurerm_network_interface" "public_app_vpn" {
  name                = "${var.prefix}-public-app-nic"
  location            = "${azurerm_resource_group.vpn.location}"
  resource_group_name = "${azurerm_resource_group.vpn.name}"
  enable_ip_forwarding          = true

  ip_configuration {
    name                          = "${var.prefix}-public-app"
    subnet_id                     = "${azurerm_subnet.public_app.id}"
    private_ip_address_allocation = "dynamic" # nope
    primary                       = true
    public_ip_address_id          = "${azurerm_public_ip.vpn.id}"
  }
}

# Interface within a network without access from internet
resource "azurerm_network_interface" "public_data_vpn" {
  name                = "${var.prefix}-public-data-nic"
  location            = "${azurerm_resource_group.vpn.location}"
  resource_group_name = "${azurerm_resource_group.vpn.name}"
  enable_ip_forwarding          = true
  ip_configuration {
    name                          = "${var.prefix}-public-data"
    subnet_id                     = "${azurerm_subnet.public_data.id}"
    private_ip_address_allocation = "dynamic" # nope
  }
}

resource "azurerm_virtual_machine" "vpn" {
  name                  = "${var.prefix}-vpn"
  location              = "${azurerm_resource_group.vpn.location}"
  resource_group_name   = "${azurerm_resource_group.vpn.name}"
  network_interface_ids = ["${azurerm_network_interface.public_app_vpn.id}"]
  vm_size               = "Standard_D2s_v3"

  delete_os_disk_on_termination = false
  delete_data_disks_on_termination = false

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.prefix}vpn"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = "50"
    os_type           = "Linux"
  }

  os_profile {
    computer_name  = "vpn.jenkins.io"
    admin_username = "azureadmin"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = "${file("${var.ssh_pubkey_path}")}"
      path = "/home/azureadmin/.ssh/authorized_keys"
    }
  }
  tags {
    env = "${var.prefix}"
  }
}
