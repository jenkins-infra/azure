# This terraform plan describe the virtual machine needed to run trusted.ci.jenkins.io
# This machine must remain in a private network.

resource "azurerm_resource_group" "trustedci" {
  name     = "${var.prefix}trustedci"
  location = "${var.location}"
  tags {
    env = "${var.prefix}"
  }
}

# This public ip is currently needed to whitelist this service on the ldap firewall.
# Once prodbean is migrated in a private network which doesn't conflict with public prod network,
# We can then remove this public IP and use private only network
resource "azurerm_public_ip" "trustedci" {
  name                         = "${var.prefix}trustedci"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.trustedci.name}"
  public_ip_address_allocation = "static"
  tags {
    env = "${var.prefix}"
  }
}

# Interface within a network without access from internet
resource "azurerm_network_interface" "trustedci_private" {
  name                    = "${var.prefix}-trustedci"
  location                = "${azurerm_resource_group.trustedci.location}"
  resource_group_name     = "${azurerm_resource_group.trustedci.name}"
  enable_ip_forwarding    = false
  internal_dns_name_label = "trustedci"
  ip_configuration {
    name                          = "${var.prefix}-private"
    subnet_id                     = "${azurerm_subnet.public_data.id}"
    private_ip_address_allocation = "static"
    private_ip_address            = "10.0.2.252"
    public_ip_address_id          = "${azurerm_public_ip.trustedci.id}"
  }
  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_virtual_machine" "trustedci" {
  name                  = "${var.prefix}-trustedci"
  location              = "${azurerm_resource_group.trustedci.location}"
  resource_group_name   = "${azurerm_resource_group.trustedci.name}"
  network_interface_ids = [
    "${azurerm_network_interface.trustedci_private.id}"
  ]
  primary_network_interface_id = "${azurerm_network_interface.trustedci_private.id}"
  vm_size               = "Standard_D2s_v3"

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.prefix}trustedci"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = "50"
    os_type           = "Linux"
  }

  os_profile {
    computer_name  = "trusted.ci.jenkins.io"
    admin_username = "azureadmin"
    custom_data    = "${ var.prefix == "prod"? file("scripts/init-puppet.sh"): "#cloud-config" }"
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

# Disk that will be used for jenkins home
resource "azurerm_managed_disk" "trustedci_data" {
  name                 = "trustedci-data"
  location             = "${azurerm_resource_group.trustedci.location}"
  resource_group_name  = "${azurerm_resource_group.trustedci.name}"
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "300"
  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "trustedci_data" {
  managed_disk_id    = "${azurerm_managed_disk.trustedci_data.id}"
  virtual_machine_id = "${azurerm_virtual_machine.trustedci.id}"
  lun                = "10"
  caching            = "ReadWrite"
}

# Create trusted ci internal endpoints
# "azure.trusted.ci" must be changed to trusted.ci, once this new machine is ready to replace the aws one
resource "azurerm_dns_a_record" "trustedci" {
  name                = "azure.trusted.ci"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600
  records             = ["${azurerm_network_interface.trustedci_private.private_ip_address}"]
}
