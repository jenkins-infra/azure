# Data of resources defined in https://github.com/jenkins-infra/azure-net
data "azurerm_resource_group" "cert_ci_jenkins_io" {
  name = "cert-ci-jenkins-io"
}
data "azurerm_dns_zone" "cert_ci_jenkins_io" {
  name                = "cert.ci.jenkins.io"
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
}

module "cert_ci_jenkins_io" {
  source = "./.shared-tools/terraform/modules/azure-jenkins-controller"

  service_fqdn                 = data.azurerm_dns_zone.cert_ci_jenkins_io.name
  location                     = data.azurerm_resource_group.cert_ci_jenkins_io.location
  admin_username               = local.admin_username
  admin_ssh_publickey          = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDpxwvySus2OWViWfJ02XMYr+Qa/uPADhjt/4el2SmEf7NlJXzq5vc8imcw8YxQZKwuuKJhonlTYTpk1Cjka4bJKWNOSQ8+Kx0O2ZnNjKn3ZETWJB90bZXHVqbrNHDtu6lN6S/yRW9Q+6fuDbHBW0MXWI8Lsv+bU5v8Zll6m62rc00/I/IT9c1TX1qjCtjf5XHMFw7nVxQiTX2Zf5UKG3RI7mkCMDIvx2H9kXdzM8jtYwATZPHKHuLzffARmvy1FpNPVuLLEGYE3hljP82rll1WZbbl1ZrhjzbFUUYO4fsA7AOQHWhHiVLvtnreB269JOl/ZkHgk37zcdwJMkqKpqoEbjP9z8PURf5uMA7TiDGcpgcFMzoaFk1ueqoHM2JaM2AZQAkPhbUfT7MSOFYRx91OEg5pg5N17zNeaBM6fyxl3v7mkxSOTkKlzjAXPRyo7XsosUVQ4qb4DfsAAJ0Rynts2olRQLEzJku0ZxbbXotuoppI8HivRl7PoTsAASJRpc="
  controller_network_name      = "cert-ci-jenkins-io-vnet"
  controller_network_rg_name   = data.azurerm_resource_group.cert_ci_jenkins_io.name
  controller_subnet_name       = "cert-ci-jenkins-io-vnet-controller"
  ephemeral_agents_subnet_name = "cert-ci-jenkins-io-vnet-ephemeral-agents"
  controller_data_disk_size_gb = 128
  controller_vm_size           = "Standard_D2as_v5"
  default_tags                 = local.default_tags

  jenkins_infra_ips = {
    ldap_ipv4           = azurerm_public_ip.ldap_jenkins_io_ipv4.ip_address
    puppet_ipv4         = azurerm_public_ip.puppet_jenkins_io.ip_address
    gpg_keyserver_ipv4s = local.gpg_keyserver_ips["keyserver.ubuntu.com"]
    privatevpn_subnet   = data.azurerm_subnet.private_vnet_data_tier.address_prefixes
  }

  controller_service_principal_ids = [
    data.azuread_service_principal.terraform_production.id,
  ]
  controller_service_principal_end_date = "2024-08-24T12:00:00Z"
  controller_packer_rg_ids = [
    azurerm_resource_group.packer_images["prod"].id
  ]
}
## Service DNS records
resource "azurerm_dns_a_record" "cert_ci_jenkins_io_controller" {
  name                = "controller"
  zone_name           = data.azurerm_dns_zone.cert_ci_jenkins_io.name
  resource_group_name = data.azurerm_dns_zone.cert_ci_jenkins_io.resource_group_name
  ttl                 = 60
  records             = [module.cert_ci_jenkins_io.controller_private_ipv4]
}
## TODO: uncomment and import when migrating
# resource "azurerm_private_dns_a_record" "cert_ci_jenkins_io" {
#   name                = "@" # Child zone: no CNAME possible!
#   zone_name           = data.azurerm_dns_zone.cert_ci_jenkins_io.name
#   resource_group_name = data.azurerm_dns_zone.cert_ci_jenkins_io.resource_group_name
#   ttl                 = 60
#   records             = [module.cert_ci_jenkins_io.controller_private_ipv4]
# }

######### Legacy resources (TODO: delete everything below once https://github.com/jenkins-infra/helpdesk/issues/3688 is migrated)
/** Two resources groups: one for the controller, the second for the agents **/
resource "azurerm_resource_group" "cert_ci_jenkins_io_controller" {
  name     = "prodcertci"
  location = "East US 2"
}

resource "azurerm_resource_group" "cert_ci_jenkins_io_agents" {
  name     = "certci-agents-2"
  location = "East US 2"
}

/** Agent Resources **/
resource "azurerm_storage_account" "cert_ci_jenkins_io_agents" {
  name                     = "certciagents2"
  resource_group_name      = azurerm_resource_group.cert_ci_jenkins_io_agents.name
  location                 = azurerm_resource_group.cert_ci_jenkins_io_agents.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # default value, needed for tfsec
  tags                     = local.default_tags
}
// TODO: import jenkinsarm-vnet virtual network

# Azure AD resources to allow controller to spawn agents in Azure
resource "azuread_application" "cert_ci_jenkins_io" {
  display_name = "cert.ci.jenkins.io"
  owners = [
    data.azuread_service_principal.terraform_production.id,
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
resource "azuread_service_principal" "cert_ci_jenkins_io" {
  application_id               = azuread_application.cert_ci_jenkins_io.application_id
  app_role_assignment_required = false
  owners = [
    data.azuread_service_principal.terraform_production.id,
  ]
}
resource "azuread_application_password" "cert_ci_jenkins_io" {
  application_object_id = azuread_application.cert_ci_jenkins_io.object_id
  display_name          = "cert.ci.jenkins.io-tf-managed"
  end_date              = "2024-03-18T00:00:00Z"
}
# Allow Service Principal to manage AzureRM resources inside the agents resource groups
resource "azurerm_role_assignment" "cert_ci_jenkins_io_allow_azurerm" {
  scope                = azurerm_resource_group.cert_ci_jenkins_io_agents.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.cert_ci_jenkins_io.id
}
resource "azurerm_role_assignment" "cert_ci_jenkins_io_allow_packer" {
  scope                = azurerm_resource_group.packer_images["prod"].id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.cert_ci_jenkins_io.id
}
