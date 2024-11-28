data "azurerm_private_link_service" "pls" {
  name                = var.pls_name
  resource_group_name = var.pls_rg_name

  provider = azurerm.pls
}

resource "azurerm_private_dns_zone" "dnszone" {
  provider = azurerm.resources

  count = var.dns_zone_name == "" ? 1 : 0

  name = var.fqdn

  resource_group_name = var.dns_rg_name
}

data "azurerm_private_dns_zone" "existing_dnszone" {
  provider = azurerm.resources

  count = var.dns_zone_name == "" ? 0 : 1

  name = var.dns_zone_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_link" {
  provider = azurerm.resources

  count = var.dns_zone_name == "" ? 1 : 0

  name                  = var.name
  resource_group_name   = var.dns_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dnszone[0].name
  virtual_network_id    = var.vnet_id

  registration_enabled = true
  tags                 = var.default_tags
}

resource "azurerm_private_endpoint" "pe" {
  provider = azurerm.resources

  name = "${data.azurerm_private_link_service.pls.name}-${var.name}"

  location            = var.location
  resource_group_name = var.rg_name
  subnet_id           = var.subnet_id

  custom_network_interface_name = "${data.azurerm_private_link_service.pls.name}-${var.name}-nic"

  private_service_connection {
    name                           = "${data.azurerm_private_link_service.pls.name}-${var.name}"
    private_connection_resource_id = data.azurerm_private_link_service.pls.id
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = var.dns_zone_name == "" ? azurerm_private_dns_zone.dnszone[0].name : data.azurerm_private_dns_zone.existing_dnszone[0].name
    private_dns_zone_ids = [var.dns_zone_name == "" ? azurerm_private_dns_zone.dnszone[0].id : data.azurerm_private_dns_zone.existing_dnszone[0].id]
  }
  tags = var.default_tags
}
resource "azurerm_private_dns_a_record" "dns_record" {
  provider = azurerm.resources

  name                = var.dns_a_record
  zone_name           = var.dns_zone_name == "" ? azurerm_private_dns_zone.dnszone[0].name : data.azurerm_private_dns_zone.existing_dnszone[0].name
  resource_group_name = var.dns_zone_name == "" ? var.dns_rg_name : data.azurerm_private_dns_zone.existing_dnszone[0].resource_group_name
  ttl                 = 60
  records             = [azurerm_private_endpoint.pe.private_service_connection[0].private_ip_address]
}
