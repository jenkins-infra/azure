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

# Azure AD resources to allow controller to spawn agents in Azure sponsored subscription
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
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_packer_sponso" {
  scope                = azurerm_resource_group.packer_images["prod"].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.object_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_allow_packer_cdf" {
  scope                = azurerm_resource_group.packer_images_cdf["prod"].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_ci_jenkins_io.object_id
}
resource "azurerm_role_assignment" "infra_ci_jenkins_io_privatek8s_sponsorship_private_vnet_reader" {
  provider           = azurerm.jenkins-sponsorship
  scope              = data.azurerm_virtual_network.private_sponsorship.id
  role_definition_id = azurerm_role_definition.private_sponsorship_vnet_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_ci_jenkins_io.object_id
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

  default_tags         = local.default_tags
  storage_account_name = "infraciagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

# Allow infra.ci VM agents to reach packer VMs with SSH on azure
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_agents_sponso_to_packer_vms" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-outbound-ssh-from-infraci-agents-sponso-to-packer-vms"
  priority               = 4080
  direction              = "Outbound"
  access                 = "Allow"
  protocol               = "Tcp"
  source_port_range      = "*"
  destination_port_range = "22"
  source_address_prefix  = data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_ephemeral_agents.address_prefix
  destination_address_prefixes = [
    data.azurerm_subnet.infra_ci_jenkins_io_sponsorship_packer_builds.address_prefix,
    data.azurerm_subnet.infra_ci_jenkins_io_packer_builds.address_prefix
  ]
  resource_group_name         = azurerm_resource_group.infra_ci_jenkins_io_controller_jenkins_sponsorship.name
  network_security_group_name = module.infra_ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_nsg_name
}

# Allow infra.ci VM agents to reach packer VMs with SSH on aws
resource "azurerm_network_security_rule" "allow_outbound_ssh_from_infraci_agents_sponso_to_aws_packer" {
  provider                    = azurerm.jenkins-sponsorship
  name                        = "allow-outbound-ssh-from-infraci-agents-sponso-to-aws-packer"
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
resource "azurerm_network_security_rule" "allow_outbound_winrm_http_from_infraci_agents_sponso_to_packer_vms" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-outbound-winrm-http-from-infraci-agents-sponso-to-packer-vms"
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
resource "azurerm_network_security_rule" "allow_outbound_winrm_https_from_infraci_agents_sponso_to_packer_vms" {
  provider               = azurerm.jenkins-sponsorship
  name                   = "allow-outbound-winrm-https-from-infraci-agents-sponso-to-packer-vms"
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
