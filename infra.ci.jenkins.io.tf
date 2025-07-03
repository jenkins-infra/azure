####################################################################################
## Sponsorship subscription specific resources for controller
####################################################################################
# This resource group hosts resources used for agents only managed by terraform or administrators
# such as NSG for agents subnet (we don't want azure-vm-agents jenkins plugin to access this RG)
resource "azurerm_resource_group" "infra_ci_jenkins_io_controller_jenkins_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "infra-ci-jenkins-io-controller"
  location = var.location
  tags     = local.default_tags
}

# Azure AD resources to allow controller to spawn agents in Azure
resource "azuread_application" "infra_ci_jenkins_io" {
  display_name = "infra.ci.jenkins.io"
  owners = [
    data.azuread_service_principal.terraform_production.object_id,
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
resource "azuread_service_principal" "infra_ci_jenkins_io" {
  client_id                    = azuread_application.infra_ci_jenkins_io.client_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.object_id,
  ]
}
resource "azuread_application_password" "infra_ci_jenkins_io" {
  application_id = azuread_application.infra_ci_jenkins_io.id
  display_name   = "infra.ci.jenkins.io-tf-managed"
  end_date       = "2025-09-07T00:00:00Z"
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_packer" {
  scope                = azurerm_resource_group.packer_images["prod"].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.object_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_read_packer" {
  provider             = azurerm.jenkins-sponsorship
  scope                = azurerm_resource_group.packer_images["prod"].id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.infra_ci_jenkins_io.principal_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_privatek8s_sponsorship_private_vnet_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = data.azurerm_virtual_network.private_sponsorship.id
  role_definition_id = azurerm_role_definition.private_sponsorship_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_ci_jenkins_io.object_id
}
resource "azurerm_user_assigned_identity" "infra_ci_jenkins_io" {
  provider            = azurerm.jenkins-sponsorship
  location            = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.location
  name                = "infracijenkinsio"
  resource_group_name = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
}

# Required to allow azcopy sync of contributors.jenkins.io File Share
module "infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn               = "infra-ci-jenkins-io-fileshare_serviceprincipal_writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = local.end_dates.infra_ci_jenkins_io.infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer.end_date
  file_share_id              = azurerm_storage_share.contributors_jenkins_io.id
  storage_account_id         = azurerm_storage_account.contributors_jenkins_io.id
  default_tags               = local.default_tags
}
output "infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}

# Required to allow azcopy sync of docs.jenkins.io File Share
module "infraci_docsjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn               = "infra-ci-jenkins-io-fileshare_serviceprincipal_writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = local.end_dates.infra_ci_jenkins_io.infraci_docsjenkinsio_fileshare_serviceprincipal_writer.end_date
  file_share_id              = azurerm_storage_share.docs_jenkins_io.id
  storage_account_id         = azurerm_storage_account.docs_jenkins_io.id
  default_tags               = local.default_tags
}
output "infraci_docsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_docsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_docsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_docsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}

# Required to allow azcopy sync of stats.jenkins.io File Share
module "infraci_statsjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn               = "infra-ci-jenkins-io-fileshare_serviceprincipal_writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = local.end_dates.infra_ci_jenkins_io.infraci_statsjenkinsio_fileshare_serviceprincipal_writer.end_date
  file_share_id              = azurerm_storage_share.stats_jenkins_io.id
  storage_account_id         = azurerm_storage_account.stats_jenkins_io.id
  default_tags               = local.default_tags
}
output "infraci_statsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_statsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_statsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_statsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}

locals {
  infra_ci_jenkins_io_fqdn                        = "infra.ci.jenkins.io"
  infra_ci_jenkins_io_service_short_name          = trimprefix(trimprefix(local.infra_ci_jenkins_io_fqdn, "jenkins.io"), ".")
  infra_ci_jenkins_io_service_short_stripped_name = replace(local.infra_ci_jenkins_io_service_short_name, ".", "-")
}

# Required to allow controller to check for subnets inside the sponsorship network
resource "azurerm_role_definition" "infra_ci_jenkins_io_controller_vnet_sponsorship_reader" {
  provider = azurerm.jenkins-sponsorship
  name     = "Read-infra-ci-jenkins-io-sponsorship-VNET"
  scope    = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "infra_controller_vnet_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.id
  role_definition_id = azurerm_role_definition.infra_ci_jenkins_io_controller_vnet_sponsorship_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_ci_jenkins_io.object_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_vnet_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = data.azurerm_virtual_network.infra_ci_jenkins_io_sponsorship.id
  role_definition_id = azurerm_role_definition.infra_ci_jenkins_io_controller_vnet_sponsorship_reader.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.infra_ci_jenkins_io.principal_id
}

module "infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship" {
  providers = {
    azurerm = azurerm.jenkins-sponsorship
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = local.infra_ci_jenkins_io_fqdn
  service_short_stripped_name      = local.infra_ci_jenkins_io_service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.name
  controller_rg_name               = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  controller_ips                   = data.azurerm_subnet.privatek8s_sponsorship_infra_ci_controller_tier.address_prefixes # Pod IPs: controller IP may change in the pods IP subnet
  controller_service_principal_id  = azuread_service_principal.infra_ci_jenkins_io.object_id
  additional_identities            = [azurerm_user_assigned_identity.infra_ci_jenkins_io.principal_id]

  default_tags         = local.default_tags
  storage_account_name = "infraciagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

# Allow infra.ci VM agents to reach packer VMs with SSH on azure
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_agents_to_packer_vms" {
  provider                    = azurerm.jenkins-sponsorship
  name                        = "allow-outbound-ssh-from-infraci-agents-to-packer-vms"
  priority                    = 4080
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefix
  destination_address_prefix  = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_packer_builds.address_prefix
  resource_group_name         = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}

# Allow infra.ci VM agents to reach packer VMs with SSH on aws
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_agents_to_aws_packer" {
  provider                    = azurerm.jenkins-sponsorship
  name                        = "allow-outbound-ssh-from-infraci-agents-to-aws-packer"
  priority                    = 4079
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefix
  destination_address_prefix  = "*" # Allow all the internet for now need to define a correct target for packer vm in aws
  resource_group_name         = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}

# Allow infra.ci VM agents to reach packer VMs with WinRM (HTTP without TLS)
resource "azurerm_network_security_rule" "allow_outbound_winrm_http_from_infraci_agents_to_packer_vms" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-outbound-winrm-http-from-infraci-agents-to-packer-vms"
  priority               = 4081
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "5985"
  source_address_prefix  = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefix
  ## Restriction to only Azure private subnet
  # destination_address_prefix  = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_packer_builds.address_prefix
  ## Allow all destinations as we cannot know the AWS EC2 public IPs of instance in advance
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}
# Allow infra.ci VM agents to reach packer VMs with WinRM (HTTPS)
resource "azurerm_network_security_rule" "allow_outbound_winrm_https_from_infraci_agents_to_packer_vms" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-outbound-winrm-https-from-infraci-agents-to-packer-vms"
  priority               = 4082
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "5986"
  source_address_prefix  = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefix
  ## Restriction to only Azure private subnet
  # destination_address_prefix  = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_packer_builds.address_prefix
  ## Allow all destinations as we cannot know the AWS EC2 public IPs of instance in advance
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}

# Required to allow azcopy sync of plugins.jenkins.io File Share
module "infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn               = "infraci-pluginsjenkinsio-fileshare_serviceprincipal_writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = local.end_dates.infra_ci_jenkins_io.infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer.end_date
  file_share_id              = azurerm_storage_share.plugins_jenkins_io.id
  storage_account_id         = azurerm_storage_account.plugins_jenkins_io.id
  default_tags               = local.default_tags
}
output "infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}

resource "azurerm_managed_disk" "jenkins_infra_data_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  name                 = "jenkins-infra-data"
  location             = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.location
  resource_group_name  = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "infra_ci_jenkins_io_controller_sponsorship_disk_reader" {
  provider = azurerm.jenkins-sponsorship
  name     = "ReadInfraCISponsorshipDisk"
  scope    = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_controller_sponsorship_disk_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.id
  role_definition_id = azurerm_role_definition.infra_ci_jenkins_io_controller_sponsorship_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
}

## Allow access to/from ACR endpoint
resource "azurerm_network_security_rule" "allow_out_https_from_infra_ephemeral_agents_to_acr" {
  provider                = azurerm.jenkins-sponsorship
  name                    = "allow-out-https-from-ephemeral-agents-to-acr"
  priority                = 4050
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["infracijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}
resource "azurerm_network_security_rule" "allow_in_https_from_infra_ephemeral_agents_to_acr" {
  provider                = azurerm.jenkins-sponsorship
  name                    = "allow-in-https-from-ephemeral-agents-to-acr"
  priority                = 4050
  direction               = "Inbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["infracijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}

resource "azurerm_user_assigned_identity" "infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  location            = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.location
  name                = "infra-ci-jenkins-io-agents-sponsorship"
  resource_group_name = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
}
# The Controller identity must be able to operate this identity to assign it to VM agents - https://plugins.jenkins.io/azure-vm-agents/#plugin-content-roles-required-by-feature
resource "azurerm_role_assignment" "infra_ci_jenkins_io_operate_agent_identity_jenkins_sponsorship" {
  provider             = azurerm.jenkins-sponsorship
  scope                = azurerm_user_assigned_identity.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.object_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship_write_buildsreports_share" {
  provider = azurerm.jenkins-sponsorship
  scope    = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.principal_id
}

resource "azurerm_user_assigned_identity" "infra_ci_jenkins_io_agents" {
  location            = var.location
  name                = "infra-ci-jenkins-io-agents"
  resource_group_name = azurerm_kubernetes_cluster.infracijenkinsio_agents_2.resource_group_name
}
# The Controller identity must be able to operate this identity to assign it to VM agents - https://plugins.jenkins.io/azure-vm-agents/#plugin-content-roles-required-by-feature
resource "azurerm_role_assignment" "infra_ci_jenkins_io_operate_agent_identity" {
  scope                = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.object_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_azurevm_agents_write_buildsreports_share" {
  scope = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents.principal_id
}

# Azure SP for updatecli with minimum rights
resource "azurerm_resource_group" "updatecli_infra_ci_jenkins_io" {
  name     = "updatecli-infra-ci-jenkins-io"
  location = var.location
}
resource "azuread_application" "updatecli_infra_ci_jenkins_io" {
  display_name = "updatecli_infra.ci.jenkins.io"
  owners = [
    # Commenting out to migrate to new AzureAD provider
    # data.azuread_service_principal.terraform_production.id,
    "b847a030-25e1-4791-ad04-9e8484d87bce",
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
    homepage_url = "https://infra.ci.jenkins.io/job/updatecli/"
  }
}
resource "azuread_service_principal" "updatecli_infra_ci_jenkins_io" {
  client_id                    = azuread_application.updatecli_infra_ci_jenkins_io.client_id
  app_role_assignment_required = false
  owners = [
    # Commenting out to migrate to new AzureAD provider
    # data.azuread_service_principal.terraform_production.id,
    "b847a030-25e1-4791-ad04-9e8484d87bce",
  ]
}
resource "azuread_application_password" "updatecli_infra_ci_jenkins_io" {
  application_id = azuread_application.updatecli_infra_ci_jenkins_io.id
  display_name   = "updatecli_infra.ci.jenkins.io-tf-managed"
  end_date       = "2025-10-01T00:00:00Z"
}

resource "azurerm_role_definition" "vm_images_reader" {
  name  = "ReadVMImages"
  scope = azurerm_resource_group.updatecli_infra_ci_jenkins_io.id

  permissions {
    actions = ["Microsoft.Compute/images/read"]
  }
}

resource "azurerm_role_assignment" "updatecli_infra_ci_jenkins_io_allow_images_list" {
  scope              = azurerm_resource_group.updatecli_infra_ci_jenkins_io.id
  role_definition_id = azurerm_role_definition.vm_images_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.updatecli_infra_ci_jenkins_io.object_id
}

resource "azurerm_key_vault" "infra_ci_jenkins_io_vault" {
  tenant_id           = data.azurerm_client_config.current.tenant_id
  name                = "prodjenkinsinfra"
  location            = "East US"
  resource_group_name = "prodjenkinsinfra"
  sku_name            = "premium"

  enabled_for_disk_encryption     = true
  soft_delete_retention_days      = 90
  purge_protection_enabled        = false
  enable_rbac_authorization       = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  public_network_access_enabled = true
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules = [
      "82.64.5.129/32",
    ]
    virtual_network_subnet_ids = local.app_subnets["infra.ci.jenkins.io"].agents
  }

  # smerle
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "0a9ca009-8333-4351-9a8a-b02244ff72b1"

    key_permissions = [
      "Encrypt",
      "Decrypt",
    ]
  }

  # dduportal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "8bb006a6-3d5f-45e0-be59-91af3db79da3"

    key_permissions = [
      "Decrypt",
      "Encrypt",
    ]
  }

  # tim jacomb
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "62ea8f6b-2604-46a6-b1cf-d2aaa15ba0c6"

    key_permissions = [
      "Decrypt",
      "Encrypt",
    ]
  }

  # infra
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = "cfcd6abd-898d-417b-8474-fc1d93705cce"

    key_permissions = [
      "Get",
      "List",
      "Purge",
      "Decrypt",
      "Encrypt",
      "Verify",
      "Sign",
    ]
  }
}
