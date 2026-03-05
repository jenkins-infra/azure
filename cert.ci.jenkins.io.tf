module "cert_ci_jenkins_io" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-controller"

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

  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.publick8s_ips["publick8s-ldap-ipv4"].ip_address,
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address,
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes,
  }

  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.object_id,
  ]
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images_cdf["prod"].id,
  ]

  agent_ip_prefixes = concat(
    data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.address_prefixes,
    data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.address_prefixes,
  )
}

module "cert_ci_jenkins_io_azurevm_agents" {
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.cert_ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.cert_ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.name
  controller_rg_name               = module.cert_ci_jenkins_io.controller_resourcegroup_name
  controller_ips                   = compact([module.cert_ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.cert_ci_jenkins_io.controller_service_principal_id
  default_tags                     = local.default_tags
  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}

resource "azurerm_user_assigned_identity" "cert_ci_jenkins_io_jenkins_agents" {
  location            = data.azurerm_virtual_network.cert_ci_jenkins_io.location
  name                = "cert-ci-jenkins-io-agents"
  resource_group_name = data.azurerm_virtual_network.cert_ci_jenkins_io.resource_group_name
}
# The Controller identity must be able to operate this identity to assign it to VM agents - https://plugins.jenkins.io/azure-vm-agents/#plugin-content-roles-required-by-feature
resource "azurerm_role_assignment" "cert_ci_jenkins_io_operate_agent_uaid" {
  scope                = azurerm_user_assigned_identity.cert_ci_jenkins_io_jenkins_agents.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = module.cert_ci_jenkins_io.controller_service_principal_id
}
resource "azurerm_role_assignment" "cert_ci_jenkins_io_azurevm_agents_jenkins_write_buildsreports_share" {
  scope = azurerm_storage_account.builds_reports_jenkins_io.id
  # Allow writing
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_ci_jenkins_io_jenkins_agents.principal_id
}


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


## Service DNS records
resource "azurerm_dns_a_record" "cert_ci_jenkins_io_controller" {
  name                = "controller"
  zone_name           = module.cert_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = module.cert_ci_jenkins_io_letsencrypt.zone_rg_name
  ttl                 = 60
  records             = [module.cert_ci_jenkins_io.controller_private_ipv4]
}
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

module "cert_ci_jenkins_io_letsencrypt" {
  source = "./modules/azure-letsencrypt-dns"

  default_tags     = local.default_tags
  zone_name        = "cert.ci.jenkins.io"
  dns_rg_name      = data.azurerm_resource_group.proddns_jenkinsio.name
  parent_zone_name = data.azurerm_dns_zone.jenkinsio.name
  principal_id     = module.cert_ci_jenkins_io.controller_service_principal_id
}

## Jenkins Sponsored
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
module "cert_ci_jenkins_io_azurevm_agents_jenkins_sponsored" {
  providers = {
    azurerm = azurerm.jenkins-sponsored
  }
  source = "./.shared-tools/terraform/modules/azure-jenkinsinfra-azurevm-agents"

  service_fqdn                     = module.cert_ci_jenkins_io.service_fqdn
  service_short_stripped_name      = module.cert_ci_jenkins_io.service_short_stripped_name
  ephemeral_agents_network_rg_name = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.resource_group_name
  ephemeral_agents_network_name    = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.virtual_network_name
  ephemeral_agents_subnet_name     = data.azurerm_subnet.cert_ci_jenkins_io_sponsored_ephemeral_agents.name
  controller_rg_name               = azurerm_resource_group.cert_ci_jenkins_io_controller_jenkins_sponsored.name
  controller_ips                   = compact([module.cert_ci_jenkins_io.controller_public_ipv4])
  controller_service_principal_id  = module.cert_ci_jenkins_io.controller_service_principal_id
  default_tags                     = local.default_tags
  storage_account_name             = "certciagentssub" # Max 24 chars

  jenkins_infra_ips = {
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }
}
