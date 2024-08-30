# Public Redis Instance
resource "azurerm_resource_group" "public_redis" {
  name     = "public-redis"
  provider = azurerm.jenkins-sponsorship
  location = var.location
  tags     = local.default_tags
}

# Redis database
resource "azurerm_redis_cache" "public_redis" {
  name                          = "public-redis"
  provider                      = azurerm.jenkins-sponsorship
  location                      = azurerm_resource_group.public_redis.location
  resource_group_name           = azurerm_resource_group.public_redis.name
  capacity                      = 2
  family                        = "P"       # Basic/Standard SKU family
  sku_name                      = "Premium" # A replicated cache in a two node Primary/Secondary configuration managed by Microsoft, with a high availability SLA.
  enable_non_ssl_port           = true
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  tags = local.default_tags
}

resource "azurerm_private_dns_zone" "public_redis" {
  # Conventional and static name required by Azure (otherwise automatic record creation does not work)
  # https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
  name = "privatelink.redis.cache.windows.net"

  # Private DNS zone name is static: we can only have one per RG
  resource_group_name = data.azurerm_subnet.publick8s_tier.resource_group_name

  tags = local.default_tags
}

resource "azurerm_private_endpoint" "public_redis" {
  name = "redis-private-endpoint"
  # provider must be the same as the using subnet

  location            = azurerm_resource_group.public_redis.location
  resource_group_name = data.azurerm_subnet.publick8s_tier.resource_group_name
  subnet_id           = data.azurerm_subnet.publick8s_tier.id

  custom_network_interface_name = "redis-nic"

  private_service_connection {
    name                           = "public-redis"
    private_connection_resource_id = azurerm_redis_cache.public_redis.id
    is_manual_connection           = false
    subresource_names              = ["redisCache"]
  }

  private_dns_zone_group {
    name                 = azurerm_private_dns_zone.public_redis.name
    private_dns_zone_ids = [azurerm_private_dns_zone.public_redis.id]
  }

}

resource "azurerm_private_dns_zone_virtual_network_link" "public_redis" {
  name = azurerm_private_dns_zone.public_redis.name

  # Private DNS zone name is static: we can only have one per RG
  resource_group_name   = data.azurerm_subnet.publick8s_tier.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.public_redis.name
  virtual_network_id    = data.azurerm_virtual_network.public.id

  registration_enabled = true
  tags                 = local.default_tags
}
