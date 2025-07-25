#### TODO: remove resources below when cleaning up for https://github.com/jenkins-infra/helpdesk/issues/4690
resource "azurerm_resource_group" "release_ci_jenkins_io_controller_jenkins_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "release-ci-jenkins-io-controller"
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_managed_disk" "jenkins_release_data_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "jenkins-release-data"
  location             = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.location
  resource_group_name  = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "release_ci_jenkins_io_controller_sponsorship_disk_reader" {
  provider = azurerm.jenkins-sponsorship
  name     = "ReadReleaseCISponsorshipDisk"
  scope    = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_controller_sponsorship_disk_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = azurerm_resource_group.release_ci_jenkins_io_controller_jenkins_sponsorship.id
  role_definition_id = azurerm_role_definition.release_ci_jenkins_io_controller_sponsorship_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
}
moved {
  from = azurerm_user_assigned_identity.release_ci_jenkins_io_agents
  to   = azurerm_user_assigned_identity.release_ci_jenkins_io_agents_sponsorship
}
resource "azurerm_user_assigned_identity" "release_ci_jenkins_io_agents_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  location            = var.location
  name                = "release-ci-jenkins-io-agents"
  resource_group_name = azurerm_kubernetes_cluster.privatek8s_sponsorship.resource_group_name
}
moved {
  from = azurerm_role_assignment.release_ci_jenkins_io_azurevm_agents_write_buildsreports_share
  to   = azurerm_role_assignment.release_ci_jenkins_io_azurevm_agents_write_buildsreports_share_sponsorship
}
resource "azurerm_role_assignment" "release_ci_jenkins_io_azurevm_agents_write_buildsreports_share_sponsorship" {
  scope = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.release_ci_jenkins_io_agents_sponsorship.principal_id
}
####
