####################################################################################
## Resources for the Controller VM in the CDF subscription
####################################################################################
module "cert_ci_jenkins_io_letsencrypt" {
  source = "./modules/azure-letsencrypt-dns"

  default_tags     = local.default_tags
  zone_name        = "cert.ci.jenkins.io"
  dns_rg_name      = data.azurerm_resource_group.proddns_jenkinsio.name
  parent_zone_name = data.azurerm_dns_zone.jenkinsio.name
  principal_ids    = [module.cert_ci_jenkins_io.controller_service_principal_id]
}
module "cert_ci_jenkins_io" {
  source = "./modules/azure-jenkinsinfra-controller"

  providers = {
    azurerm     = azurerm
    azurerm.dns = azurerm
    azuread     = azuread
  }

  service_fqdn                 = module.cert_ci_jenkins_io_letsencrypt.zone_name
  location                     = data.azurerm_resource_group.cert_ci_jenkins_io.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDpxwvySus2OWViWfJ02XMYr+Qa/uPADhjt/4el2SmEf7NlJXzq5vc8imcw8YxQZKwuuKJhonlTYTpk1Cjka4bJKWNOSQ8+Kx0O2ZnNjKn3ZETWJB90bZXHVqbrNHDtu6lN6S/yRW9Q+6fuDbHBW0MXWI8Lsv+bU5v8Zll6m62rc00/I/IT9c1TX1qjCtjf5XHMFw7nVxQiTX2Zf5UKG3RI7mkCMDIvx2H9kXdzM8jtYwATZPHKHuLzffARmvy1FpNPVuLLEGYE3hljP82rll1WZbbl1ZrhjzbFUUYO4fsA7AOQHWhHiVLvtnreB269JOl/ZkHgk37zcdwJMkqKpqoEbjP9z8PURf5uMA7TiDGcpgcFMzoaFk1ueqoHM2JaM2AZQAkPhbUfT7MSOFYRx91OEg5pg5N17zNeaBM6fyxl3v7mkxSOTkKlzjAXPRyo7XsosUVQ4qb4DfsAAJ0Rynts2olRQLEzJku0ZxbbXotuoppI8HivRl7PoTsAASJRpc="
  controller_network_name      = data.azurerm_virtual_network.cert_ci_jenkins_io.name
  controller_network_rg_name   = data.azurerm_resource_group.cert_ci_jenkins_io.name
  controller_subnet_name       = data.azurerm_subnet.cert_ci_jenkins_io_controller.name
  controller_data_disk_size_gb = 128
  controller_vm_size           = "Standard_B2s"
  default_tags                 = local.default_tags
  dns_zone_name                = module.cert_ci_jenkins_io_letsencrypt.zone_name
  dns_resourcegroup_name       = module.cert_ci_jenkins_io_letsencrypt.zone_rg_name

  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.publick8s_ips["publick8s-ldap-ipv4"].ip_address,
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address,
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
  }

  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.object_id,
  ]
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images_sponsored["prod"].id,
  ]

  agent_ip_prefixes = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.address_prefixes
}

####################################################################################
## Agents resources in the CDF subscription
####################################################################################
# Required to allow controller to check for subnets inside the virtual network
resource "azurerm_role_definition" "cert_ci_jenkins_io_vnet_reader" {
  name  = "read-cert-ci-jenkins-io-vnet"
  scope = data.azurerm_virtual_network.cert_ci_jenkins_io.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "cert_ci_jenkins_io_controller_vnet_reader" {
  scope              = data.azurerm_virtual_network.cert_ci_jenkins_io.id
  role_definition_id = azurerm_role_definition.cert_ci_jenkins_io_vnet_reader.role_definition_resource_id
  principal_id       = module.cert_ci_jenkins_io.controller_service_principal_id
}

####################################################################################
## Agents resources in the sponsored subscription
####################################################################################
module "cert_ci_jenkins_io_azurevm_agents_jenkins_sponsored" {
  providers = {
    azurerm = azurerm.jenkins-sponsored
  }
  source = "./modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.cert_ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.cert_ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.name
  use_vnet_common_nsg              = true
  controller_ips                   = compact([module.cert_ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_ids = [module.cert_ci_jenkins_io.controller_service_principal_id]
  default_tags                     = local.default_tags
  storage_account_name             = "certciagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}
resource "azurerm_resource_group" "cert_ci_jenkins_io_controller_jenkins_sponsored" {
  provider = azurerm.jenkins-sponsored
  name     = module.cert_ci_jenkins_io.controller_resourcegroup_name # Same name on both subscriptions
  location = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsored.location
  tags     = local.default_tags
}
resource "azurerm_user_assigned_identity" "cert_ci_jenkins_io_azurevm_agents_jenkins_sponsored" {
  provider            = azurerm.jenkins-sponsored
  location            = azurerm_resource_group.cert_ci_jenkins_io_controller_jenkins_sponsored.location
  name                = "cert-ci-jenkins-io-agents-sponsored"
  resource_group_name = azurerm_resource_group.cert_ci_jenkins_io_controller_jenkins_sponsored.name
}
# The Controller identity must be able to operate this identity to assign it to VM agents - https://plugins.jenkins.io/azure-vm-agents/#plugin-content-roles-required-by-feature
resource "azurerm_role_assignment" "cert_ci_jenkins_io_operate_agent_identity_jenkins_sponsored" {
  provider             = azurerm.jenkins-sponsored
  scope                = azurerm_user_assigned_identity.cert_ci_jenkins_io_azurevm_agents_jenkins_sponsored.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = module.cert_ci_jenkins_io.controller_service_principal_id
}
resource "azurerm_role_assignment" "cert_ci_jenkins_io_azurevm_agents_jenkins_sponsored_write_buildsreports_share" {
  provider = azurerm.jenkins-sponsored
  scope    = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_ci_jenkins_io_azurevm_agents_jenkins_sponsored.principal_id
}
resource "azurerm_role_definition" "cert_ci_jenkins_io_controller_vnet_sponsored_reader" {
  provider = azurerm.jenkins-sponsored
  name     = "Read-cert-ci-jenkins-io-sponsored-VNET"
  scope    = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsored.id

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/read"]
  }
}
resource "azurerm_role_assignment" "cert_controller_vnet_jenkins_sponsored_reader" {
  provider           = azurerm.jenkins-sponsored
  scope              = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsored.id
  role_definition_id = azurerm_role_definition.cert_ci_jenkins_io_controller_vnet_sponsored_reader.role_definition_resource_id
  principal_id       = module.cert_ci_jenkins_io.controller_service_principal_id
}
####################################################################################
## Common resources (endpoint, DNS, etc.) in the sponsored subscription
####################################################################################
resource "azurerm_resource_group" "cert_ci_jenkins_io_sponsored_commons" {
  provider = azurerm.jenkins-sponsored
  name     = "cert-ci-jenkins-io-sponsored-commons"
  location = var.location
  tags     = local.default_tags
}
# Managed in jenkins-infra/azure-net with vnet and subnets
data "azurerm_network_security_group" "cert_ci_jenkins_io_sponsored_vnet" {
  provider = azurerm.jenkins-sponsored

  name                = "cert-ci-jenkins-io-sponsored-vnet"
  resource_group_name = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.resource_group_name
}
# Allow access to the private Azure Container Registry through an Azure Private Endpoint NIC
module "certcijenkinsiosponsored_acr_pe" {
  source = "./modules/azure-container-registry-private-links"

  providers = {
    azurerm     = azurerm.jenkins-sponsored
    azurerm.acr = azurerm
  }

  name = "certcijenkinsiosponsored"

  acr_name     = azurerm_container_registry.dockerhub_mirror.name
  acr_location = azurerm_container_registry.dockerhub_mirror.location
  acr_rg_name  = azurerm_container_registry.dockerhub_mirror.resource_group_name

  subnet_name  = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_commons.name
  vnet_name    = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsored.name
  vnet_rg_name = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsored.resource_group_name

  default_tags = local.default_tags
}
## Allow access to/from Private Endpoint
resource "azurerm_network_security_rule" "allow_out_https_from_cert_sponsored_vnet_to_acr" {
  provider = azurerm.jenkins-sponsored

  name                         = "allow-out-https-from-sponsored-vnet-to-acr"
  priority                     = 4052
  direction                    = "Outbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "443"
  source_address_prefixes      = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsored.address_space
  destination_address_prefixes = split(",", module.certcijenkinsiosponsored_acr_pe.private_endpoint_nic_ip_addresses)
  resource_group_name          = data.azurerm_network_security_group.cert_ci_jenkins_io_sponsored_vnet.resource_group_name
  network_security_group_name  = data.azurerm_network_security_group.cert_ci_jenkins_io_sponsored_vnet.name
}
resource "azurerm_network_security_rule" "allow_in_https_from_cert_sponsored_vnet_to_acr" {
  provider = azurerm.jenkins-sponsored

  name                         = "allow-in-https-from-sponsored-vnet-to-acr"
  priority                     = 4052
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "443"
  source_address_prefixes      = data.azurerm_virtual_network.cert_ci_jenkins_io_sponsored.address_space
  destination_address_prefixes = split(",", module.certcijenkinsiosponsored_acr_pe.private_endpoint_nic_ip_addresses)
  resource_group_name          = data.azurerm_network_security_group.cert_ci_jenkins_io_sponsored_vnet.resource_group_name
  network_security_group_name  = data.azurerm_network_security_group.cert_ci_jenkins_io_sponsored_vnet.name
}
resource "azuread_application" "cert_ci_jenkins_io_acr_dockerhub_mirror" {
  display_name = "cert-ci-jenkins-io-acr-dockerhub-mirror"
  owners = [
    data.azuread_service_principal.terraform_production.client_id,
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
    homepage_url = "https://cert.ci.jenkins.io/manage/credentials/store/system/domain/_/credential/azure-container-registry-push/"
  }
}
# resource "azuread_service_principal" "cert_ci_jenkins_io_acr_dockerhub_mirror" {
#   client_id                    = azuread_application.cert_ci_jenkins_io_acr_dockerhub_mirror.client_id
#   app_role_assignment_required = false
#   owners = [
#     data.azuread_service_principal.terraform_production.id,
#   ]
# }
resource "azuread_application_password" "cert_ci_jenkins_io_acr_dockerhub_mirror" {
  application_id = azuread_application.cert_ci_jenkins_io_acr_dockerhub_mirror.id
  display_name   = "cert-ci-jenkins-io-acr-dockerhub-mirror"
  # end_date       = "2026-11-22T00:00:00Z"
}
resource "azurerm_role_assignment" "certpush_to_acr" {
  count                            = var.environment == "staging" ? 0 : 1
  principal_id                     = azuread_application.cert_ci_jenkins_io_acr_dockerhub_mirror.client_id
  role_definition_name             = "AcrPush"
  scope                            = azurerm_container_registry.dockerhub_mirror.id
  skip_service_principal_aad_check = true
}

####################################################################################
## Public DNS records in the CDF subscription
####################################################################################
resource "azurerm_dns_a_record" "cert_ci_jenkins_io" {
  name                = "@" # Child zone: no CNAME possible!
  zone_name           = module.cert_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = module.cert_ci_jenkins_io_letsencrypt.zone_rg_name
  ttl                 = 60
  records             = [module.cert_ci_jenkins_io.controller_private_ipv4]
}
resource "azurerm_dns_a_record" "assets_cert_ci_jenkins_io" {
  name                = "assets"
  zone_name           = module.cert_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = module.cert_ci_jenkins_io_letsencrypt.zone_rg_name
  ttl                 = 60
  records             = [module.cert_ci_jenkins_io.controller_private_ipv4]
}
