#### ACR to use as DockerHub (and other) Registry mirror
resource "azurerm_resource_group" "dockerhub_mirror" {
  name     = "dockerhub-mirror"
  location = var.location
}

resource "azurerm_container_registry" "dockerhub_mirror" {
  name                          = "dockerhubmirror"
  resource_group_name           = azurerm_resource_group.dockerhub_mirror.name
  location                      = azurerm_resource_group.dockerhub_mirror.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false # private links are used to reach the registry
  anonymous_pull_enabled        = true  # Requires "Standard" or "Premium" sku. Docker Engine cannot use auth. for pull trough cache - ref. https://github.com/moby/moby/issues/30880
  data_endpoint_enabled         = true  # Required for endpoint private link. Requires "Premium" sku.

  tags = local.default_tags
}

locals {
  acr_private_links = {
    "certcijenkinsio" = {
      "subnet_id" = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.id,
      "vnet_id"   = data.azurerm_virtual_network.cert_ci_jenkins_io.id
      "rg_name"   = data.azurerm_virtual_network.cert_ci_jenkins_io.resource_group_name
    },
    "infracijenkinsio" = {
      "subnet_id" = data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.id,
      "vnet_id"   = data.azurerm_virtual_network.infra_ci_jenkins_io.id
      "rg_name"   = data.azurerm_virtual_network.infra_ci_jenkins_io.resource_group_name
    },
  }
}

resource "azurerm_private_endpoint" "dockerhub_mirror" {
  for_each = local.acr_private_links

  name = "acr-${each.key}"

  location            = azurerm_resource_group.dockerhub_mirror.location
  resource_group_name = azurerm_resource_group.dockerhub_mirror.name
  subnet_id           = each.value.subnet_id

  custom_network_interface_name = "acr-${each.key}-nic"

  private_service_connection {
    name                           = "acr-${each.key}"
    private_connection_resource_id = azurerm_container_registry.dockerhub_mirror.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "privatelink.azurecr.io"
    private_dns_zone_ids = [azurerm_private_dns_zone.dockerhub_mirror[each.key].id]
  }
  tags = local.default_tags
}

resource "azurerm_private_dns_zone" "dockerhub_mirror" {
  for_each = local.acr_private_links

  # Conventional and static name required by Azure (otherwise automatic record creation does not work)
  name = "privatelink.azurecr.io"

  # Private DNS zone name is static: we can only have one per RG
  resource_group_name = each.value.rg_name

  tags = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dockerhub_mirror" {
  for_each = local.acr_private_links

  name = "privatelink.azurecr.io"
  # Private DNS zone name is static: we can only have one per RG
  resource_group_name   = each.value.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dockerhub_mirror[each.key].name
  virtual_network_id    = each.value.vnet_id

  registration_enabled = true
  tags                 = local.default_tags
}

## TODO: factorize and simplify RBAC policy with other keyvaults
#trivy:ignore:avd-azu-0016
resource "azurerm_key_vault" "dockerhub_mirror" {
  name                = "dockerhubmirror"
  location            = azurerm_resource_group.dockerhub_mirror.location
  resource_group_name = azurerm_resource_group.dockerhub_mirror.name

  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false
  enable_rbac_authorization       = true
  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  public_network_access_enabled = true
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = local.app_subnets["infra.ci.jenkins.io"].agents
  }

  # smerle
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "0a9ca009-8333-4351-9a8a-b02244ff72b1"

    key_permissions = [
      "Encrypt",
      "Decrypt",
    ]
  }

  # dduportal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "8bb006a6-3d5f-45e0-be59-91af3db79da3"

    key_permissions = [
      "Decrypt",
      "Encrypt",
    ]
  }

  # tim jacomb
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "62ea8f6b-2604-46a6-b1cf-d2aaa15ba0c6"

    key_permissions = [
      "Decrypt",
      "Encrypt",
    ]
  }

  # infra
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "cfcd6abd-898d-417b-8474-fc1d93705cce"

    key_permissions = [
      "Get",
      "List",
      "Purge",
      "Decrypt",
      "Encrypt",
      "Verify",
      "Sign",
    ]
  }

  sku_name = "standard"

  tags = local.default_tags
}

# # IMPORTANT: when bootstrapping, multiple Terraform apply are required until ACR CredentialSet can be created by Terraform (unsupported by Terraform until https://github.com/hashicorp/terraform-provider-azurerm/issues/26539 is done).
# # 1. Start by creating the dockerhub-username and docker-password in the Keyvault (once created) which requires the "Key Vault Secrets Officer"  or "Owner" role temporarily
# # 2. Then create the CredentialSet in the registry (once created) with the name 'dockerhub'. It will be marked as "Unhealthy" (expected).
# # 3. Then retrieve the principal ID and set it in the attributes below.
# # 4. Finally re-run terraform apply one last time to create this azurerm_role_assignment and the ACR cache rule. The CredentialSet in ACR will be marked as "Healthy" right after this apply.
# resource "azurerm_role_assignment" "acr_read_keyvault_secrets" {
#   provider                         = azurerm.jenkins-sponsorship
#   scope                            = azurerm_key_vault.dockerhub_mirror.id
#   role_definition_name             = "Key Vault Secrets User"
#   skip_service_principal_aad_check = true
#   # Need to be retrieved manually from Azure UI -> Container Registries -> Select the "azurerm_key_vault.dockerhub_mirror" resource -> Services -> Cache -> Credentials -> select "dockerhub"
#   principal_id = "90872c87-43ab-446d-89b2-741693c34b90"
# }

# resource "azurerm_container_registry_cache_rule" "mirror_dockerhub" {
#   name                  = "mirror"
#   provider              = azurerm.jenkins-sponsorship
#   container_registry_id = azurerm_container_registry.dockerhub_mirror.id
#   source_repo           = "docker.io/*"
#   target_repo           = "*"

#   # Credential created manually (unsupported by Terraform until https://github.com/hashicorp/terraform-provider-azurerm/issues/26539 is done).
#   # Check dependent resource
#   depends_on        = [azurerm_role_assignment.acr_read_keyvault_secrets]
#   credential_set_id = "${azurerm_container_registry.dockerhub_mirror.id}/credentialSets/dockerhub"
# }
