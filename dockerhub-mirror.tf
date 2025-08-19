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
      "vnet_id"   = data.azurerm_virtual_network.cert_ci_jenkins_io.id,
      "rg_name"   = data.azurerm_virtual_network.cert_ci_jenkins_io.resource_group_name,
    },
    "infracijenkinsio" = {
      "subnet_id" = data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.id,
      "vnet_id"   = data.azurerm_virtual_network.infra_ci_jenkins_io.id,
      "rg_name"   = data.azurerm_virtual_network.infra_ci_jenkins_io.resource_group_name,
    },
    "publick8s" = {
      "subnet_id" = data.azurerm_subnet.publick8s_tier.id,
      "vnet_id"   = data.azurerm_virtual_network.public.id,
      "rg_name"   = data.azurerm_resource_group.public.name,
    },
    "privatek8s" = {
      "subnet_id" = data.azurerm_subnet.privatek8s_tier.id,
      "vnet_id"   = data.azurerm_virtual_network.private.id,
      "rg_name"   = data.azurerm_resource_group.private.name,
    },
    "trustedcijenkinsio" = {
      "subnet_id" = data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.id,
      "vnet_id"   = data.azurerm_virtual_network.trusted_ci_jenkins_io.id,
      "rg_name"   = data.azurerm_virtual_network.trusted_ci_jenkins_io.resource_group_name,
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
    name = "privatelink.azurecr.io"
    private_dns_zone_ids = [
      (can(each.value["private_dns_zone_id"]) ? each.value["private_dns_zone_id"] : azurerm_private_dns_zone.dockerhub_mirror[each.key].id),
    ]
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

  sku_name = "standard"

  tags = local.default_tags
}

# IMPORTANT: when bootstrapping, 2 distincts "terraform apply" are required:
# 1. The first one must create the Keyvault (at least: can do the ACR and Private Endpoints/DNS/network links).
# 2. Then, the 2 secrets must be manually created with the respective names "dockerhub-username" and "dockerhub-password"
# 3. Finally, the set of "data.azurerm_key_vault_secret" + ACR CredentialSet + Role assignement + Registry Cache rule can be created as a 2nd terraform deployment
resource "azurerm_container_registry_credential_set" "dockerhub" {
  name                  = "dockerhub"
  container_registry_id = azurerm_container_registry.dockerhub_mirror.id
  login_server          = "docker.io"
  identity {
    type = "SystemAssigned"
  }
  authentication_credentials {
    username_secret_id = "${azurerm_key_vault.dockerhub_mirror.vault_uri}secrets/dockerhub-username"
    password_secret_id = "${azurerm_key_vault.dockerhub_mirror.vault_uri}secrets/dockerhub-password"
  }
}
resource "azurerm_role_assignment" "acr_read_keyvault_secrets" {
  scope                            = azurerm_key_vault.dockerhub_mirror.id
  role_definition_name             = "Key Vault Secrets User"
  skip_service_principal_aad_check = true
  principal_id                     = azurerm_container_registry_credential_set.dockerhub.identity[0].principal_id
}

resource "azurerm_container_registry_cache_rule" "mirror_cache_rules" {
  for_each = {
    "dockerhub-library-namespace" = {
      source = "docker.io/library/*"
      target = "library/*"
    },
    "dockerhub-jenkins-namespace" = {
      source = "docker.io/jenkins/*"
      target = "jenkins/*"
    }
    "dockerhub-moby-namespace" = {
      source = "docker.io/moby/*"
      target = "moby/*"
    }
    # Also used on AWS (ci.jenkins.io)
    "dockerhub-jenkinsciinfra-builder" = {
      source = "docker.io/jenkinsciinfra/builder"
      target = "jenkinsciinfra/builder"
    }
    # Also used on AWS (ci.jenkins.io)
    "dockerhub-jenkinsciinfra-jau-2204" = {
      source = "docker.io/jenkinsciinfra/jenkins-agent-ubuntu-22.04"
      target = "jenkinsciinfra/jenkins-agent-ubuntu-22.04"
    }
    # Also used on AWS (ci.jenkins.io)
    "dockerhub-jenkinsciinfra-packaging" = {
      source = "docker.io/jenkinsciinfra/packaging"
      target = "jenkinsciinfra/packaging"
    }
    # Used by ATH image build
    "dockerhub-rockstorm-git-server" = {
      source = "docker.io/rockstorm/git-server"
      target = "rockstorm/git-server"
    }
    # Used by ATH image build
    "dockerhub-testcontainers-ryuk" = {
      source = "docker.io/testcontainers/ryuk"
      target = "testcontainers/ryuk"
    }
  }
  name                  = "mirror-${each.key}"
  container_registry_id = azurerm_container_registry.dockerhub_mirror.id
  source_repo           = each.value.source
  target_repo           = each.value.target
  credential_set_id     = azurerm_container_registry_credential_set.dockerhub.id
}

#### Allow provided Principal IDs to push images to the registry
resource "azurerm_role_assignment" "push_to_acr" {
  for_each = var.terratest ? toset([]) : toset([
    azurerm_user_assigned_identity.infra_ci_jenkins_io_agents.principal_id,
  ])
  principal_id                     = each.value
  role_definition_name             = "AcrPush"
  scope                            = azurerm_container_registry.dockerhub_mirror.id
  skip_service_principal_aad_check = true
}
