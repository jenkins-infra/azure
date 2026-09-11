####################################################################################
## Azure Active Directory Resources to allow manipulating file shares
####################################################################################
resource "azuread_application" "fileshare_serviceprincipal_writer" {
  display_name = var.service_fqdn
  owners       = var.active_directory_owners
  tags         = [for key, value in var.default_tags : "${key}:${value}"]
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  web {
    homepage_url = var.active_directory_url
  }
}
resource "azuread_application_password" "fileshare_serviceprincipal_writer" {
  application_id = azuread_application.fileshare_serviceprincipal_writer.id
  display_name   = "${var.service_fqdn}-tf-managed"
  end_date       = var.service_principal_end_date
}

resource "azuread_service_principal" "fileshare_serviceprincipal_writer" {
  client_id                    = azuread_application.fileshare_serviceprincipal_writer.client_id
  app_role_assignment_required = false
  owners                       = var.active_directory_owners
}
resource "azuread_service_principal_password" "fileshare_serviceprincipal_writer" {
  service_principal_id = azuread_service_principal.fileshare_serviceprincipal_writer.id
}

# https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-authorize-azure-active-directory#verify-role-assignments
resource "azurerm_role_assignment" "file_share_privileged_contributor" {
  scope                = var.file_share_id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azuread_service_principal.fileshare_serviceprincipal_writer.object_id
}

# Needed so the service principal can access the Storage Account access key to generate a SAS token
resource "azurerm_role_assignment" "storage_account_privileged_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azuread_service_principal.fileshare_serviceprincipal_writer.object_id
}
