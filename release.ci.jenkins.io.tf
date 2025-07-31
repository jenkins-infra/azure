resource "azurerm_resource_group" "release_ci_jenkins_io_controller" {
  name     = "release-ci-jenkins-io-controller"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_user_assigned_identity" "release_ci_jenkins_io_controller" {
  location            = azurerm_resource_group.release_ci_jenkins_io_controller.location
  name                = "releasecijenkinsiocontroller"
  resource_group_name = azurerm_resource_group.release_ci_jenkins_io_controller.name
}
resource "azurerm_managed_disk" "release_ci_jenkins_io_data" {
  name                 = "release-ci-jenkins-io-data"
  location             = azurerm_resource_group.release_ci_jenkins_io_controller.location
  resource_group_name  = azurerm_resource_group.release_ci_jenkins_io_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "release_ci_jenkins_io_controller_disk_reader" {
  name  = "ReadReleaseCIDisk"
  scope = azurerm_resource_group.release_ci_jenkins_io_controller.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_controller_disk_reader" {
  scope              = azurerm_resource_group.release_ci_jenkins_io_controller.id
  role_definition_id = azurerm_role_definition.release_ci_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
}
resource "azurerm_user_assigned_identity" "release_ci_jenkins_io_agents" {
  location            = var.location
  name                = "release-ci-jenkins-io-agents"
  resource_group_name = azurerm_kubernetes_cluster.privatek8s.resource_group_name
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_azurevm_agents_write_buildsreports_share" {
  scope = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.release_ci_jenkins_io_agents.principal_id
}

resource "azurerm_resource_group" "prodreleasecore" {
  name     = "prodreleasecore"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_key_vault" "prodreleasecore" {
  tenant_id           = data.azurerm_client_config.current.tenant_id
  name                = "prodreleasecore"
  location            = var.location
  resource_group_name = azurerm_resource_group.prodreleasecore.name
  sku_name            = "standard"

  enabled_for_disk_encryption     = false
  soft_delete_retention_days      = 90
  purge_protection_enabled        = false
  enable_rbac_authorization       = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  public_network_access_enabled = true
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = local.app_subnets["release.ci.jenkins.io"].agents
  }

  # releasecore Entra Application
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "b6d73004-673f-4099-aa80-30e6e9dae314"

    certificate_permissions = [
      "Get",
      "List",
      "GetIssuers",
      "ListIssuers",
    ]

    key_permissions = [
      "Get",
      "List",
      "Decrypt",
      "Verify",
      "Encrypt",
    ]
    secret_permissions = [
      "Get",
      "List",
    ]
  }
}
