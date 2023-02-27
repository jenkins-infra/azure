resource "azuread_application" "trusted_ci_jenkins_io" {
  display_name = "trusted.ci.jenkins.io"
  owners       = [data.azuread_client_config.current.object_id]
  tags         = [for key, value in local.default_tags : "${key}:${value}"]
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000"

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
  }

  web {
    homepage_url = "https://github.com/jenkins-infra/azure"
  }
}

resource "azuread_service_principal" "trusted_ci_jenkins_io" {
  application_id = azuread_application.trusted_ci_jenkins_io.application_id
}

resource "time_rotating" "trusted_ci_jenkins_io" {
  rotation_days = 365
}

resource "azuread_application_password" "trusted_ci_jenkins_io" {
  display_name          = "trusted.ci.jenkins.io-tf-managed"
  application_object_id = azuread_application.trusted_ci_jenkins_io.id
  rotate_when_changed = {
    rotation = time_rotating.trusted_ci_jenkins_io.id
  }
}
