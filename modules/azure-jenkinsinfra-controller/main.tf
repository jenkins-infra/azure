####################################################################################
# Network resources defined in https://github.com/jenkins-infra/azure-net
####################################################################################
data "azurerm_resource_group" "controller" {
  name = var.controller_network_rg_name
}
data "azurerm_virtual_network" "controller" {
  name                = var.controller_network_name
  resource_group_name = data.azurerm_resource_group.controller.name
}
data "azurerm_subnet" "controller" {
  name                 = var.controller_subnet_name
  virtual_network_name = data.azurerm_virtual_network.controller.name
  resource_group_name  = data.azurerm_resource_group.controller.name
}

####################################################################################
## Resources for the Controller VM
####################################################################################
resource "azurerm_resource_group" "controller" {
  name     = var.controller_resourcegroup_name == "" ? "${local.service_stripped_name}-controller" : var.controller_resourcegroup_name
  location = var.location
  tags     = var.default_tags
}
resource "azurerm_public_ip" "controller" {
  count               = var.is_public ? 1 : 0
  name                = local.controller_fqdn
  location            = azurerm_resource_group.controller.location
  resource_group_name = azurerm_resource_group.controller.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.default_tags
}
resource "azurerm_management_lock" "controller_publicip" {
  count      = var.is_public ? 1 : 0
  name       = "${local.service_stripped_name}-controller-publicip"
  scope      = azurerm_public_ip.controller[0].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed"
}
resource "azurerm_public_ip" "controller_ipv6" {
  count               = var.is_public && var.enable_public_ipv6 ? 1 : 0
  name                = "${local.controller_fqdn}-ipv6"
  location            = azurerm_resource_group.controller.location
  resource_group_name = azurerm_resource_group.controller.name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv6"
  tags                = var.default_tags
}
resource "azurerm_management_lock" "controller_publicipv6" {
  count      = var.is_public && var.enable_public_ipv6 ? 1 : 0
  name       = "${local.service_stripped_name}-controller-publicipv6"
  scope      = azurerm_public_ip.controller_ipv6[0].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed"
}
data "azurerm_dns_zone" "controller" {
  count               = var.is_public && var.dns_zone_name != "" ? 1 : 0
  provider            = azurerm.dns
  name                = var.dns_zone_name
  resource_group_name = var.dns_resourcegroup_name
}
resource "azurerm_dns_a_record" "controller" {
  count               = length(data.azurerm_dns_zone.controller)
  provider            = azurerm.dns
  name                = trimsuffix(trimsuffix(local.controller_fqdn, var.dns_zone), ".")
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_resourcegroup_name
  ttl                 = 60
  records             = [azurerm_public_ip.controller[0].ip_address]
  tags                = var.default_tags
}
resource "azurerm_dns_a_record" "private_controller" {
  count               = length(data.azurerm_dns_zone.controller)
  provider            = azurerm.dns
  name                = "private.${azurerm_dns_a_record.controller[0].name}"
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_resourcegroup_name
  ttl                 = 60
  records             = [azurerm_network_interface.controller.private_ip_address]
  tags                = var.default_tags
}
resource "azurerm_network_interface" "controller" {
  name                = local.controller_fqdn
  location            = azurerm_resource_group.controller.location
  resource_group_name = azurerm_resource_group.controller.name
  tags                = var.default_tags

  ip_configuration {
    name                          = var.is_public ? "external" : "internal"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.is_public ? azurerm_public_ip.controller[0].id : null
    private_ip_address_version    = "IPv4"
    subnet_id                     = data.azurerm_subnet.controller.id
    primary                       = true
  }

  dynamic "ip_configuration" {
    for_each = var.is_public && var.enable_public_ipv6 ? ["IPv6"] : []
    content {
      name                          = var.is_public ? "external-ipv6" : "internal-ipv6"
      private_ip_address_allocation = "Dynamic"
      public_ip_address_id          = var.is_public ? azurerm_public_ip.controller_ipv6[0].id : null
      private_ip_address_version    = "IPv6"
      subnet_id                     = data.azurerm_subnet.controller.id
      primary                       = false
    }
  }
}
resource "azurerm_managed_disk" "controller_data" {
  name                 = var.controller_datadisk_name == "" ? "${local.controller_fqdn}-data" : var.controller_datadisk_name
  location             = azurerm_resource_group.controller.location
  resource_group_name  = azurerm_resource_group.controller.name
  storage_account_type = var.controller_data_disk_type
  create_option        = "Empty"
  disk_size_gb         = var.controller_data_disk_size_gb

  tags = var.default_tags
}
## trick to avoid dynamics/static on locals to fail
data "azurerm_virtual_machine" "controller" {
  name                = azurerm_linux_virtual_machine.controller.name
  resource_group_name = azurerm_linux_virtual_machine.controller.resource_group_name
}
resource "azurerm_linux_virtual_machine" "controller" {
  name                            = local.controller_fqdn
  resource_group_name             = azurerm_resource_group.controller.name
  location                        = azurerm_resource_group.controller.location
  tags                            = var.default_tags
  size                            = var.controller_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.controller.id,
  ]

  dynamic "identity" {
    for_each = var.controller_service_principal_end_date == "" ? ["SystemAssigned"] : []
    content {
      type = "SystemAssigned"
    }
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_publickey
  }

  user_data = base64encode(
    templatefile("${path.root}/.shared-tools/terraform/cloudinit.tftpl", {
      hostname       = local.controller_fqdn,
      admin_username = var.admin_username,
    })
  )
  computer_name = local.controller_fqdn

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.controller_os_disk_type
    disk_size_gb         = var.controller_os_disk_size_gb
  }

  # Instances with a 'p' in their vm size are 'arm64' which requires a different image (SKU/offer)
  source_image_reference {
    publisher = "Canonical"
    offer     = strcontains(var.controller_vm_size, "p") ? "0001-com-ubuntu-server-jammy" : "0001-com-ubuntu-minimal-jammy"
    sku       = strcontains(var.controller_vm_size, "p") ? "22_04-lts-arm64" : "minimal-22_04-lts-gen2"
    version   = "latest"
  }
}
resource "azurerm_virtual_machine_data_disk_attachment" "controller_data" {
  managed_disk_id    = azurerm_managed_disk.controller_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.controller.id
  lun                = "10"
  caching            = "ReadWrite"
}

####################################################################################
## Network Security Group and rules
####################################################################################
### Controller
resource "azurerm_network_security_group" "controller" {
  name                = local.controller_fqdn
  location            = var.location
  resource_group_name = azurerm_resource_group.controller.name
  tags                = var.default_tags
}
resource "azurerm_subnet_network_security_group_association" "controller" {
  subnet_id                 = data.azurerm_subnet.controller.id
  network_security_group_id = azurerm_network_security_group.controller.id
}

## Outbound Rules (different set of priorities than Inbound rules) ##
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_controller_to_agents" {
  name                         = "allow-outbound-ssh-from-${local.service_short_stripped_name}-controller-to-agents"
  priority                     = 4085
  direction                    = "Outbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  source_address_prefix        = azurerm_linux_virtual_machine.controller.private_ip_address
  destination_port_range       = "22" # SSH
  destination_address_prefixes = var.agent_ip_prefixes
  resource_group_name          = azurerm_resource_group.controller.name
  network_security_group_name  = azurerm_network_security_group.controller.name
}
# Ignore the rule as it does not detect the IP restriction to only ldap.jenkins.io"s host
resource "azurerm_network_security_rule" "allow_outbound_ldap_from_controller_to_jenkinsldap" {
  name                        = "allow-outbound-ldap-from-${local.service_short_stripped_name}-controller-to-jenkinsldap"
  priority                    = 4086
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = azurerm_linux_virtual_machine.controller.private_ip_address
  destination_port_range      = "636" # LDAP over TLS
  destination_address_prefix  = var.jenkins_infra_ips.ldap_ipv4
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
}
# Ignore the rule as it does not detect the IP restriction to only puppet.jenkins.io"s host
resource "azurerm_network_security_rule" "allow_outbound_puppet_from_controller_to_puppetmaster" {
  name                        = "allow-outbound-puppet-from-${local.service_short_stripped_name}-controller-to-puppetmaster"
  priority                    = 4087
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = azurerm_linux_virtual_machine.controller.private_ip_address
  destination_port_range      = "8140" # Puppet over TLS
  destination_address_prefix  = var.jenkins_infra_ips.puppet_ipv4
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
}
resource "azurerm_network_security_rule" "allow_outbound_http_from_controller_to_internet" {
  name                        = "allow-outbound-http-from-${local.service_short_stripped_name}-controller-to-internet"
  priority                    = 4089
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = azurerm_linux_virtual_machine.controller.private_ip_address
  destination_port_ranges     = ["80", "443"]
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
}
# This rule overrides an Azure-Default rule. its priority must be < 65000.
resource "azurerm_network_security_rule" "deny_all_outbound_from_controller_subnet" {
  name                        = "deny-all-outbound-from-${local.service_short_stripped_name}-controller"
  priority                    = 4096 # Maximum value allowed by the provider
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = azurerm_linux_virtual_machine.controller.private_ip_address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
}

## Inbound Rules (different set of priorities than Outbound rules) ##
resource "azurerm_network_security_rule" "allow_inbound_ssh_from_privatevpn_to_controller" {
  name                        = "allow-inbound-ssh-from-privatevpn-to-${local.service_short_stripped_name}-controller"
  priority                    = 4085
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
  source_address_prefixes     = var.jenkins_infra_ips.privatevpn_subnet
  destination_address_prefixes = compact([
    azurerm_linux_virtual_machine.controller.private_ip_address,
    var.is_public ? azurerm_public_ip.controller[0].ip_address : "",
  ])
}

resource "azurerm_network_security_rule" "allow_inbound_jenkins_to_controller" {
  name                  = "allow-inbound-jenkins-to-${local.service_short_stripped_name}-controller"
  priority              = 4080
  direction             = "Inbound"
  access                = "Allow"
  protocol              = "Tcp"
  source_port_range     = "*"
  source_address_prefix = var.is_public ? "*" : "VirtualNetwork"
  destination_port_ranges = [
    "80",    # HTTP (for redirections to HTTPS)
    "443",   # HTTPS
    "50000", # Direct TCP Inbound protocol
  ]
  destination_address_prefixes = compact(flatten([
    [for ip in azurerm_linux_virtual_machine.controller.private_ip_addresses :
      ip if can(cidrnetmask("${ip}/32"))
    ],
    var.is_public ? azurerm_public_ip.controller[0].ip_address : "",
  ]))
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
}
resource "azurerm_network_security_rule" "allow_inbound_http6_to_controller" {
  count                 = var.is_public && var.enable_public_ipv6 ? 1 : 0
  name                  = "allow-inbound-http6-to-${local.service_short_stripped_name}-controller"
  priority              = 4081
  direction             = "Inbound"
  access                = "Allow"
  protocol              = "Tcp"
  source_port_range     = "*"
  source_address_prefix = var.is_public ? "*" : "VirtualNetwork"
  destination_port_ranges = [
    "80",  # HTTP (for redirections to HTTPS)
    "443", # HTTPS
  ]
  destination_address_prefixes = compact(flatten([
    [for ip in azurerm_linux_virtual_machine.controller.private_ip_addresses :
      ip if !can(cidrnetmask("${ip}/32"))
    ],
    azurerm_public_ip.controller_ipv6[0].ip_address,
  ]))
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
}

# This rule overrides an Azure-Default rule. its priority must be < 65000
# Please note that Azure NSG default to "deny all inbound from Internet"
resource "azurerm_network_security_rule" "deny_all_inbound_to_controller" {
  name                   = "deny-all-inbound-to-${local.service_short_stripped_name}-controller"
  priority               = 4090 # Maximum value allowed by the Azure Terraform Provider is 4096
  direction              = "Inbound"
  access                 = "Deny"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"
  source_address_prefix  = "*"
  destination_address_prefixes = compact([
    azurerm_linux_virtual_machine.controller.private_ip_address,
    var.is_public ? azurerm_public_ip.controller[0].ip_address : "",
  ])
  resource_group_name         = azurerm_resource_group.controller.name
  network_security_group_name = azurerm_network_security_group.controller.name
}

####################################################################################
## Azure Active Directory Resources to allow controller spawning azure agents
####################################################################################
resource "azuread_application" "controller" {
  count        = var.controller_service_principal_end_date == "" ? 0 : 1
  display_name = local.service_custom_name
  owners       = var.controller_service_principal_ids
  tags         = [for key, value in var.default_tags : "${key}:${value}"]
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  web {
    homepage_url = var.controller_active_directory_url
  }
}
resource "azuread_service_principal" "controller" {
  count                        = var.controller_service_principal_end_date == "" ? 0 : 1
  client_id                    = azuread_application.controller[0].client_id
  app_role_assignment_required = false
  owners                       = var.controller_service_principal_ids
}
resource "azuread_application_password" "controller" {
  count          = var.controller_service_principal_end_date == "" ? 0 : 1
  application_id = azuread_application.controller[0].id
  display_name   = "${var.service_fqdn}-tf-managed"
  end_date       = var.controller_service_principal_end_date
}
resource "azurerm_role_assignment" "controller_read_packer_prod_images" {
  count                = length(var.controller_packer_rg_ids)
  scope                = var.controller_packer_rg_ids[count.index]
  role_definition_name = "Reader"
  principal_id         = local.controller_principal_id
  depends_on           = [azurerm_linux_virtual_machine.controller]
}
resource "azurerm_role_definition" "controller_vnet_reader" {
  name  = "Read-${local.service_custom_name}-VNET"
  scope = data.azurerm_virtual_network.controller.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "controller_vnet_reader" {
  scope              = data.azurerm_virtual_network.controller.id
  role_definition_id = azurerm_role_definition.controller_vnet_reader.role_definition_resource_id
  principal_id       = local.controller_principal_id
  depends_on         = [azurerm_linux_virtual_machine.controller]
}
