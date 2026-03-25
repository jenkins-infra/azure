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

## TODO: factorize and simplify RBAC policy with other keyvaults
#trivy:ignore:avd-azu-0016
resource "azurerm_key_vault" "dockerhub_mirror" {
  name                = "dockerhubmirror"
  location            = azurerm_resource_group.dockerhub_mirror.location
  resource_group_name = azurerm_resource_group.dockerhub_mirror.name

  tenant_id                       = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false
  rbac_authorization_enabled      = true
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
# id obtained with `terraform state list | grep push_to_acr`
moved {
  from = azurerm_role_assignment.push_to_acr["4b7d8dbc-c30d-43ca-8112-fd8be2cca3b0"]
  to   = azurerm_role_assignment.push_to_acr[0]
}
resource "azurerm_role_assignment" "push_to_acr" {
  count = var.terratest ? 0 : 1
  principal_id                     = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents_jenkins_sponsored.principal_id
  role_definition_name             = "AcrPush"
  scope                            = azurerm_container_registry.dockerhub_mirror.id
  skip_service_principal_aad_check = true
}
