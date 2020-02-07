# This terraform plan describe the virtual machine needed to run ci.jenkins.io

resource "azurerm_public_ip" "ci" {
  name                         = "${var.prefix}ci"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.ci.name
  public_ip_address_allocation = "static"

  tags = {
    env = var.prefix
  }
}

resource "azurerm_network_interface" "ci_public" {
  name                    = "${var.prefix}-ci"
  location                = azurerm_resource_group.ci.location
  resource_group_name     = azurerm_resource_group.ci.name
  enable_ip_forwarding    = false
  internal_dns_name_label = "ci"

  ip_configuration {
    name                          = "${var.prefix}-public"
    subnet_id                     = azurerm_subnet.public_data.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.ci.id
  }

  tags = {
    env = var.prefix
  }
}

resource "azurerm_virtual_machine" "ci" {
  name                = "${var.prefix}-ci"
  location            = azurerm_resource_group.ci.location
  resource_group_name = azurerm_resource_group.ci.name

  network_interface_ids = [
    azurerm_network_interface.ci_public.id,
  ]

  primary_network_interface_id = azurerm_network_interface.ci_public.id
  vm_size                      = "Standard_D8s_v3"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.prefix}ci"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = "50"
    os_type           = "Linux"
  }

  os_profile {
    computer_name  = "ci.jenkins.io"
    admin_username = "azureadmin"
    custom_data    = var.prefix == "prod" ? file("scripts/init-puppet.sh") : "#cloud-config"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      key_data = file(var.ssh_pubkey_path)
      path     = "/home/azureadmin/.ssh/authorized_keys"
    }
  }

  tags = {
    env = var.prefix
  }
}

# Disk that will be used for jenkins home
resource "azurerm_managed_disk" "ci_data" {
  name                 = "ci-data"
  location             = azurerm_resource_group.ci.location
  resource_group_name  = azurerm_resource_group.ci.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "300"

  tags = {
    env = var.prefix
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "ci_data" {
  managed_disk_id    = azurerm_managed_disk.ci_data.id
  virtual_machine_id = azurerm_virtual_machine.ci.id
  lun                = "10"
  caching            = "ReadWrite"
}

