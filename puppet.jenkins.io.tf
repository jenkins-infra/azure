resource "azurerm_resource_group" "puppet_jenkins_io" {
  name     = "puppet.jenkins.io"
  location = "East US 2"
  tags     = local.default_tags
}
resource "azurerm_public_ip" "puppet_jenkins_io" {
  name                = "puppet.jenkins.io"
  location            = azurerm_resource_group.puppet_jenkins_io.location
  resource_group_name = azurerm_resource_group.puppet_jenkins_io.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "puppet_jenkins_io_publicip" {
  name       = "puppet.jenkins.io-publicip"
  scope      = azurerm_public_ip.puppet_jenkins_io.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed"
}
# Defined in https://github.com/jenkins-infra/azure-net/tree/main/vnets.tf
data "azurerm_subnet" "dmz" {
  name                 = "${data.azurerm_virtual_network.private.name}-dmz"
  resource_group_name  = data.azurerm_resource_group.private.name
  virtual_network_name = data.azurerm_virtual_network.private.name
}
resource "azurerm_network_interface" "puppet_jenkins_io" {
  name                = "puppet.jenkins.io"
  location            = azurerm_resource_group.puppet_jenkins_io.location
  resource_group_name = azurerm_resource_group.puppet_jenkins_io.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "external"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.puppet_jenkins_io.id
    subnet_id                     = data.azurerm_subnet.dmz.id
  }
}
data "azurerm_network_security_group" "private_dmz" {
  name = "${data.azurerm_virtual_network.private.name}-dmz"
  # location            = data.azurerm_resource_group.private.name.location
  resource_group_name = data.azurerm_resource_group.private.name
}
## Inbound Rules (different set of priorities than Outbound rules) ##
#tfsec:ignore:azure-network-no-public-ingress
resource "azurerm_network_security_rule" "allow_inbound_webhooks_from_github_to_puppet" {
  name              = "allow-inbound-webhooks-from-github-to-puppet"
  priority          = 3999
  direction         = "Inbound"
  access            = "Allow"
  protocol          = "Tcp"
  source_port_range = "*"
  # https://github.com/jenkins-infra/jenkins-infra/blob/51c90220ec19ed688a0605dce4a98eddd212844a/dist/profile/manifests/r10k.pp
  # https://forge.puppet.com/modules/puppet/r10k/readme
  destination_port_range      = "8088" # r10k webhook default port
  source_address_prefixes     = local.github_ips.webhooks
  destination_address_prefix  = azurerm_linux_virtual_machine.puppet_jenkins_io.private_ip_address
  resource_group_name         = data.azurerm_resource_group.private.name
  network_security_group_name = data.azurerm_network_security_group.private_dmz.name
}
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_admins_to_puppet" {
  name                        = "allow-inbound-ssh-from-admins-to-puppet"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = values(local.admin_allowed_ips)
  destination_address_prefix  = azurerm_linux_virtual_machine.puppet_jenkins_io.private_ip_address
  resource_group_name         = data.azurerm_resource_group.private.name
  network_security_group_name = data.azurerm_network_security_group.private_dmz.name
}
#tfsec:ignore:azure-network-no-public-ingress
resource "azurerm_network_security_rule" "allow_inbound_puppet_from_vms" {
  name                        = "allow-inbound-puppet-from-vms"
  priority                    = 4001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8140"
  source_address_prefix       = "Internet" # TODO: restrict to only our VM outbound IPs
  destination_address_prefix  = azurerm_linux_virtual_machine.puppet_jenkins_io.private_ip_address
  resource_group_name         = data.azurerm_resource_group.private.name
  network_security_group_name = data.azurerm_network_security_group.private_dmz.name
}
## Outbound Rules (different set of priorities than Inbound rules) ##
resource "azurerm_network_security_rule" "allow_outbound_http_from_puppet_to_internet" {
  name                        = "allow-outbound-http-from-puppet-to-internet"
  priority                    = 4002
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = azurerm_linux_virtual_machine.puppet_jenkins_io.private_ip_address
  destination_port_ranges     = ["80", "443"]
  destination_address_prefix  = "Internet"
  resource_group_name         = data.azurerm_resource_group.private.name
  network_security_group_name = data.azurerm_network_security_group.private_dmz.name
}
resource "azurerm_linux_virtual_machine" "puppet_jenkins_io" {
  name                            = "puppet.jenkins.io"
  resource_group_name             = azurerm_resource_group.puppet_jenkins_io.name
  location                        = azurerm_resource_group.puppet_jenkins_io.location
  tags                            = local.default_tags
  size                            = "Standard_D2as_v5"
  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.puppet_jenkins_io.id,
  ]

  admin_ssh_key {
    username   = local.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC54ZdYuBsHL4gtLA40hF55HdwB6g//lu5VOdpSaMP3z+dvQUUYGF+6CRxvmmr2j9+bxD/8+aJY8mBqQU2dLhhwjQIOl2gZCisWhNBGM+4oX7N/BjCAF4vc7oN5obrbI+rjauwoN0rUdT5jVvAXspVXx9Hl3ZlT/oCqogLzzbG7r8nJXNGfDASyKjRnOhjraTVhYnttgkOsQgMVNua5KuDGmtJQeshCysBZ16A3qOTblTDebUybbSjtgpRmYyfVAQqSqMTQygR2RrpbGvNj77L79z05a0TpBbDluDNLkjVAlrZ7FmNd7M4jyuLAwPStM3tHnPkXAPPVucO5cPI3l5KJNRNUxX37jRFU7tdN7NbSku8qxxoyFal67PvVU01+6xGlc5JbPVaUd621JYH8je5g+y4VMhv2o06FH5D7NXXHf809qR32xUbvPMOcBKjBZYDX+1DgHH2hMm3ezlcKgh707XQGAAIAvM5rZPXfe4MpgF9s0XEB4MXMhLSyNJ2uros="
  }
  computer_name = "puppet.jenkins.io"

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 32 # Minimal size for ubuntu 20.04 image
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-minimal-focal"
    sku       = "minimal-20_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_dns_a_record" "azure_puppet_jenkins_io" {
  name                = "azure.puppet"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_public_ip.puppet_jenkins_io.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_cname_record" "jenkinsio_target_puppet_jenkins_io" {
  name                = "puppet"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  record              = azurerm_dns_a_record.azure_puppet_jenkins_io.fqdn
  tags                = local.default_tags
}
