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
