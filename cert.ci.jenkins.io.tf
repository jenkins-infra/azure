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
  controller_vm_size           = "Standard_D2as_v5"
  default_tags                 = local.default_tags

  jenkins_infra_ips = {
    ldap_ipv4         = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
    puppet_ipv4       = azurerm_public_ip.puppet_jenkins_io.ip_address
    privatevpn_subnet = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }

  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.object_id,
  ]
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images["prod"].id
  ]

  agent_ip_prefixes = concat(
    data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.address_prefixes,
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

## Allow access to/from ACR endpoint
resource "azurerm_network_security_rule" "allow_out_https_from_cert_agents_to_acr" {
  name                    = "allow-out-https-from-agents-to-acr"
  priority                = 4050
  direction               = "Outbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["certcijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}
resource "azurerm_network_security_rule" "allow_in_https_from_cert_agents_to_acr" {
  name                    = "allow-in-https-from-agents-to-acr"
  priority                = 4050
  direction               = "Inbound"
  access                  = "Allow"
  protocol                = "Tcp"
  source_port_range       = "*"
  destination_port_range  = "443"
  source_address_prefixes = data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.address_prefixes
  destination_address_prefixes = distinct(
    flatten(
      [for rs in azurerm_private_endpoint.dockerhub_mirror["certcijenkinsio"].private_dns_zone_configs.*.record_sets : rs.*.ip_addresses]
    )
  )
  resource_group_name         = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_rg_name
  network_security_group_name = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_nsg_name
}

module "cert_ci_jenkins_io_letsencrypt" {
  source = "./.shared-tools/terraform/modules/azure-letsencrypt-dns"

  default_tags     = local.default_tags
  zone_name        = "cert.ci.jenkins.io"
  dns_rg_name      = data.azurerm_resource_group.proddns_jenkinsio.name
  parent_zone_name = data.azurerm_dns_zone.jenkinsio.name
  principal_id     = module.cert_ci_jenkins_io.controller_service_principal_id
}
