resource "azuread_application" "trusted_ci_jenkins_io" {
  display_name = "trusted.ci.jenkins.io"
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
  tags = [for key, value in local.default_tags : "${key}:${value}"]
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }

  web {
    homepage_url = "https://github.com/jenkins-infra/azure"
  }
}

resource "azuread_service_principal" "trusted_ci_jenkins_io" {
  application_id               = azuread_application.trusted_ci_jenkins_io.application_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
}

resource "azuread_application_password" "trusted_ci_jenkins_io" {
  application_object_id = azuread_application.trusted_ci_jenkins_io.object_id
  display_name          = "trusted.ci.jenkins.io-tf-managed"
  end_date              = "2024-03-08T19:40:35Z"
}

# Allow Service Principal to manage AzureRM resources inside the subscription
# TODO lower this scope to the resource group
resource "azurerm_role_assignment" "trusted_ci_jenkins_io_allow_azurerm" {
  scope                = data.azurerm_subscription.jenkins.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.trusted_ci_jenkins_io.id
}
