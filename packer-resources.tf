# Azure Resources required or used by the repository jenkins-infra/packer-images

resource "azuread_application" "packer" {
  display_name = "packer"
  owners = [
    data.azuread_service_principal.terraform_production.object_id, # terraform-production Service Principal, used by the CI system
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

resource "azuread_service_principal" "packer" {
  client_id                    = azuread_application.packer.client_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.object_id, # terraform-production Service Principal, used by the CI system
  ]
}

resource "azuread_application_password" "packer" {
  display_name   = "packer-tf-managed"
  application_id = azuread_application.packer.id
  end_date       = "2024-12-09T00:00:00Z"
}

## Dev Resources are used by the pull requests in jenkins-infra/packer-images
## Staging Resources are used by the "main" branch builds
## Prod Resources are used for final Packer artifacts
resource "azurerm_resource_group" "packer_images" {
  provider = azurerm.jenkins-sponsorship
  for_each = local.shared_galleries

  name     = "${each.key}-packer-images"
  location = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.location # Location of the packer subnet in infra.ci
}

resource "azurerm_resource_group" "packer_builds" {
  provider = azurerm.jenkins-sponsorship
  for_each = local.shared_galleries

  name     = "${each.key}-packer-builds"
  location = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.location # Location of the packer subnet in infra.ci
}

resource "azurerm_shared_image_gallery" "packer_images" {
  provider = azurerm.jenkins-sponsorship

  for_each = local.shared_galleries

  name                = "${each.key}_packer_images"
  resource_group_name = azurerm_resource_group.packer_images[each.key].name
  location            = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.location # Location of the packer subnet in infra.ci
  description         = each.value.description

  tags = {
    scope = "terraform-managed"
  }
}

# Note that Terraform does NOT manage image versions (it's packer-based).
resource "azurerm_shared_image" "jenkins_agent_images" {
  provider = azurerm.jenkins-sponsorship

  # Generate a list of images in the form "<gallery name>_<image_name>"
  for_each = toset(
    distinct(
      flatten([
        for gallery_key, gallery_value in local.shared_galleries : [
          for image_key in gallery_value.images : "${gallery_key}_${image_key}"
        ]
      ])
    )
  )

  name                = format("jenkins-agent-%s", split("_", each.value)[1])
  gallery_name        = azurerm_shared_image_gallery.packer_images[split("_", each.value)[0]].name
  resource_group_name = azurerm_resource_group.packer_images[split("_", each.value)[0]].name
  location            = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.location # Location of the packer subnet in infra.ci

  architecture = length(regexall(".+arm64", split("_", each.value)[1])) > 0 ? "Arm64" : "x64"

  hyper_v_generation     = "V2"
  os_type                = length(regexall(".*windows.*", lower(split("_", each.value)[1]))) > 0 ? "Windows" : "Linux"
  specialized            = false
  trusted_launch_enabled = false

  lifecycle {
    ignore_changes = [
      eula, accelerated_network_support_enabled
    ]
  }

  identifier {
    publisher = format("jenkins-agent-%s", split("_", each.value)[1])
    offer     = format("jenkins-agent-%s", split("_", each.value)[1])
    sku       = format("jenkins-agent-%s", split("_", each.value)[1])
  }

  tags = {
    scope = "terraform-managed"
  }
}

# Allow packer Service Principal to manage AzureRM resources inside the packer resource groups
resource "azurerm_role_assignment" "packer_role_images_assignement" {
  provider = azurerm.jenkins-sponsorship
  for_each = azurerm_resource_group.packer_images

  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.packer.id
}
# Allow packer Service Principal to manage AzureRM resources inside the packer resource groups
resource "azurerm_role_assignment" "packer_role_builds_assignement" {
  provider = azurerm.jenkins-sponsorship
  for_each = azurerm_resource_group.packer_builds

  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.packer.id
}
resource "azurerm_role_assignment" "packer_role_manage_subnet" {
  provider             = azurerm.jenkins-sponsorship
  scope                = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_packer_builds.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.packer.id
}
