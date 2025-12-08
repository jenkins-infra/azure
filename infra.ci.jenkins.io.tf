# This resource group hosts resources used for agents only managed by terraform or administrators
# such as NSG for agents subnet (we don't want azure-vm-agents jenkins plugin to access this RG)
resource "azurerm_resource_group" "infra_ci_jenkins_io_controller" {
  name     = "infra-ci-jenkins-io-controller"
  location = var.location
  tags     = local.default_tags
}
resource "azurerm_user_assigned_identity" "infra_ci_jenkins_io_controller" {
  location            = azurerm_resource_group.infra_ci_jenkins_io_controller.location
  name                = "infracijenkinsiocontroller"
  resource_group_name = azurerm_resource_group.infra_ci_jenkins_io_controller.name
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

# Required to allow azcopy sync to the reports.jenkins.io File Share
module "infraci_reportsjenkinsio_fileshare_serviceprincipal_writer" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-fileshare-serviceprincipal-writer"

  service_fqdn               = "infraci-reportsjenkinsio-fileshare_serviceprincipal_writer"
  active_directory_owners    = [data.azuread_service_principal.terraform_production.object_id]
  active_directory_url       = "https://github.com/jenkins-infra/azure"
  service_principal_end_date = "2025-12-23T00:00:00Z"
  file_share_id              = azurerm_storage_share.reports_jenkins_io.id
  storage_account_id         = azurerm_storage_account.reports_jenkins_io.id
  default_tags               = local.default_tags
}

# Required to allow controller to check for subnets inside the virtual network
resource "azurerm_role_definition" "infra_ci_jenkins_io_controller_vnet_reader" {
  name  = "read-infra-ci-jenkins-io-vnet"
  scope = data.azurerm_virtual_network.infra_ci_jenkins_io.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_controller_vnet_reader" {
  scope              = data.azurerm_virtual_network.infra_ci_jenkins_io.id
  role_definition_id = azurerm_role_definition.infra_ci_jenkins_io_controller_vnet_reader.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller.principal_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_packer" {
  scope                = azurerm_resource_group.packer_images_cdf["prod"].id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller.principal_id
}
module "infra_ci_jenkins_io_azurevm_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = local.infra_ci_jenkins_io_fqdn
  service_short_stripped_name      = local.infra_ci_jenkins_io_service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.name
  controller_rg_name               = azurerm_resource_group.infra_ci_jenkins_io_controller.name
  controller_ips                   = data.azurerm_subnet.privatek8s_infra_ci_controller_tier.address_prefixes # Pod IPs: controller IP may change in the pods IP subnet
  controller_service_principal_id  = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller.principal_id

  default_tags = local.default_tags

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

# Allow infra.ci VM agents to reach packer VMs with SSH on azure
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_agents_to_packer_vms" {
  name                   = "allow-outbound-ssh-from-infraci-agents-to-packer-vms"
  priority               = 4080
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "22"
  source_address_prefixes = [
    data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix,
    data.azurerm_subnet.infracijenkinsio_agents_2.address_prefix,
  ]
  destination_address_prefix  = data.azurerm_subnet.infra_ci_jenkins_io_packer_builds.address_prefix
  resource_group_name         = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

# Allow infra.ci VM agents to reach packer VMs with SSH on aws
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_agents_to_aws_packer" {
  name                   = "allow-outbound-ssh-from-infraci-agents-to-aws-packer"
  priority               = 4079
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "22"
  source_address_prefixes = [
    data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix,
    data.azurerm_subnet.infracijenkinsio_agents_2.address_prefix,
  ]
  # Allow all destinations as we cannot know the AWS EC2 public IPs of instance in advance
  destination_address_prefix  = "*"
  resource_group_name         = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

# Allow infra.ci VM agents to reach packer VMs with WinRM (HTTP without TLS)
resource "azurerm_network_security_rule" "allow_outbound_winrm_http_from_infraci_agents_to_packer_vms" {
  name                   = "allow-outbound-winrm-http-from-infraci-agents-to-packer-vms"
  priority               = 4081
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "5985"
  source_address_prefixes = [
    data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix,
    data.azurerm_subnet.infracijenkinsio_agents_2.address_prefix,
  ]
  # Allow all destinations as we cannot know the AWS EC2 public IPs of instance in advance
  destination_address_prefix  = "*"
  resource_group_name         = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}
# Allow infra.ci VM agents to reach packer VMs with WinRM (HTTPS)
resource "azurerm_network_security_rule" "allow_outbound_winrm_https_from_infraci_agents_to_packer_vms" {
  name                   = "allow-outbound-winrm-https-from-infraci-agents-to-packer-vms"
  priority               = 4082
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "5986"
  source_address_prefixes = [
    data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix,
    data.azurerm_subnet.infracijenkinsio_agents_2.address_prefix,
  ]
  # Allow all destinations as we cannot know the AWS EC2 public IPs of instance in advance
  destination_address_prefix  = "*"
  resource_group_name         = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

# Allow infra.ci VM agents to reach AKS clusters with SSH on azure
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_ephemeral_agents_to_aks_clusters" {
  for_each                = local.aks_clusters_only
  name                    = "allow-outbound-ssh-from-infraci-agents-to-${each.key}"
  priority                = 4083 + index(keys(local.aks_clusters_only), each.key) # 3 AKS clusters
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = [data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix]
  # TODO: restrict to required resources only
  destination_address_prefixes = [local.aks_clusters_only[each.key].subnet_address_prefix]
  resource_group_name          = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name  = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

# Allow infra.ci VM agents to reach databases hosted on Azure with SSH on azure
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_ephemeral_agents_to_azure_dbs" {
  for_each                     = local.azure_dbs_subnet_address_prefixes
  name                         = "allow-outbound-ssh-from-infraci-agents-to-${each.key}"
  priority                     = 4086 + index(keys(local.azure_dbs_subnet_address_prefixes), each.key)
  direction                    = "Outbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "443"
  source_address_prefixes      = [data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix]
  destination_address_prefixes = [each.value]
  resource_group_name          = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name  = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
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

resource "azurerm_managed_disk" "infra_ci_jenkins_io_data" {
  name                 = "infra-ci-jenkins-io-data"
  location             = azurerm_resource_group.infra_ci_jenkins_io_controller.location
  resource_group_name  = azurerm_resource_group.infra_ci_jenkins_io_controller.name
  storage_account_type = "StandardSSD_ZRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = local.default_tags
}
# Required to allow AKS CSI driver to access the Azure disk
resource "azurerm_role_definition" "infra_ci_jenkins_io_controller_disk_reader" {
  name  = "ReadInfraCIDisk"
  scope = azurerm_resource_group.infra_ci_jenkins_io_controller.id

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
    ]
  }
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_controller_disk_reader" {
  scope              = azurerm_resource_group.infra_ci_jenkins_io_controller.id
  role_definition_id = azurerm_role_definition.infra_ci_jenkins_io_controller_disk_reader.role_definition_resource_id
  principal_id       = azurerm_kubernetes_cluster.privatek8s.identity[0].principal_id
}

## Allow access to/from ACR endpoint
resource "azurerm_network_security_rule" "allow_out_https_from_infra_ephemeral_agents_to_acr" {
  count                  = var.terratest ? 0 : 1
  name                   = "allow-out-https-from-ephemeral-agents-to-acr"
  priority               = 4050
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "443"
  source_address_prefixes = [
    data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix,
    data.azurerm_subnet.infracijenkinsio_agents_2.address_prefix,
  ]
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["infracijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}
resource "azurerm_network_security_rule" "allow_in_https_from_infra_ephemeral_agents_to_acr" {
  count                  = var.terratest ? 0 : 1
  name                   = "allow-in-https-from-ephemeral-agents-to-acr"
  priority               = 4050
  direction              = "Inbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "443"
  source_address_prefixes = [
    data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.address_prefix,
    data.azurerm_subnet.infracijenkinsio_agents_2.address_prefix,
  ]
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["infracijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

## Identity assigned to agents workloads (allowing them to reach resources without any Azure credential)
resource "azurerm_user_assigned_identity" "infra_ci_jenkins_io_agents" {
  location            = var.location
  name                = "infra-ci-jenkins-io-agents"
  resource_group_name = azurerm_resource_group.infra_ci_jenkins_io_controller.name
}
# The Controller identity must be able to operate this identity to assign it to VM agents - https://plugins.jenkins.io/azure-vm-agents/#plugin-content-roles-required-by-feature
resource "azurerm_role_assignment" "infra_ci_jenkins_io_operate_agents_identity" {
  scope                = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.infra_ci_jenkins_io_controller.principal_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_agents_write_buildsreports_share" {
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
  end_date       = "2025-12-23T00:00:00Z"
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
  rbac_authorization_enabled      = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  public_network_access_enabled = true
  # Adding a network rule with `public_network_access_enabled` set to `true` (default) selects the option "Enabled from selected virtual networks and IP addresses"
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
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

  # jenkinsinfraSOPS
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
