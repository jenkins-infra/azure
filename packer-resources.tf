# Azure Resources required or used by the repository jenkins-infra/packer-images

resource "azuread_application" "packer" {
  display_name = "packer"
  owners = [
    data.azuread_service_principal.terraform_production.id, # terraform-production Service Principal, used by the CI system
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
  application_id               = azuread_application.packer.application_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id, # terraform-production Service Principal, used by the CI system
  ]
}

resource "azuread_application_password" "packer" {
  display_name          = "packer-tf-managed"
  application_object_id = azuread_application.packer.object_id
  end_date              = "2024-03-09T11:00:00Z"
}


## Dev Resources are used by the pull requests in jenkins-infra/packer-images
## Staging Resources are used by the "main" branch builds
## Prod Resources are used for final Packer artifacts
resource "azurerm_resource_group" "packer_images" {
  for_each = local.shared_galleries

  name     = "${each.key}-packer-images"
  location = each.value.rg_location
}

resource "azurerm_resource_group" "packer_builds" {
  for_each = local.shared_galleries

  name     = "${each.key}-packer-builds"
  location = each.value.rg_location
}

resource "azurerm_shared_image_gallery" "packer_images" {
  for_each = local.shared_galleries

  name                = "${each.key}_packer_images"
  resource_group_name = azurerm_resource_group.packer_images[each.key].name
  location            = "eastus" #azurerm_resource_group.packer_images[each.key].location
  description         = each.value.description

  tags = {
    scope = "terraform-managed"
  }
}

# Note that Terraform does NOT manage image versions (it's packer-based).
resource "azurerm_shared_image" "jenkins_agent_images" {
  # Generate a list of images in the form "<gallery name>_<image_name>"
  for_each = toset(
    distinct(
      flatten([
        for gallery_key, gallery_value in local.shared_galleries : [
          for image_key, image_value in gallery_value.images_location : "${gallery_key}_${image_key}"
        ]
      ])
    )
  )

  name                = format("jenkins-agent-%s", split("_", each.value)[1])
  gallery_name        = azurerm_shared_image_gallery.packer_images[split("_", each.value)[0]].name
  resource_group_name = azurerm_resource_group.packer_images[split("_", each.value)[0]].name
  location            = local.shared_galleries[split("_", each.value)[0]].images_location[split("_", each.value)[1]]

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
  for_each = azurerm_resource_group.packer_images

  scope                = "subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${each.value.name}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.packer.id
}
# Allow packer Service Principal to manage AzureRM resources inside the packer resource groups
resource "azurerm_role_assignment" "packer_role_builds_assignement" {
  for_each = azurerm_resource_group.packer_builds

  scope                = "subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${each.value.name}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.packer.id
}
