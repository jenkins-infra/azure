## This file contains the resources associated to the buckets used to store private and public reports

############# Legacy resources to be removed once migrated to the new resources below
resource "azurerm_resource_group" "prod_reports" {
  name     = "prod-reports"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_account" "prodjenkinsreports" {
  name                       = "prodjenkinsreports"
  resource_group_name        = azurerm_resource_group.prod_reports.name
  location                   = azurerm_resource_group.prod_reports.location
  account_tier               = "Standard"
  account_replication_type   = "GRS"
  account_kind               = "Storage"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = {
    scope = "terraform-managed"
  }
}
############# End of legacy resources to be removed once migrated to the new resources below

resource "azurerm_resource_group" "reports_jenkins_io" {
  name     = "reports-jenkins-io"
  location = var.location

  tags = {
    scope = "terraform-managed"
  }
}
resource "azurerm_storage_account" "reports_jenkins_io" {
  name                       = "reportsjenkinsio"
  resource_group_name        = azurerm_resource_group.reports_jenkins_io.name
  location                   = azurerm_resource_group.reports_jenkins_io.location
  account_tier               = "Standard"
  account_replication_type   = "ZRS"
  account_kind               = "StorageV2"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  network_rules {
    default_action = "Deny"
    ip_rules = flatten(concat(
      [for key, value in module.jenkins_infra_shared_data.admin_public_ips : value]
    ))
    virtual_network_subnet_ids = concat(
      [
        # Required for using the resource
        data.azurerm_subnet.publick8s_tier.id,
      ],
      # Required for managing and populating the resource
      local.app_subnets["infra.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["release.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["trusted.ci.jenkins.io"].agents,
      # Required for populating the resource
      local.app_subnets["cert.ci.jenkins.io"].agents,
    )
    bypass = ["AzureServices"]
  }

  tags = {
    scope = "terraform-managed"
  }
}

# Resources used for builds.reports.jenkins.io web service
resource "azurerm_storage_share" "builds_reports_jenkins_io" {
  name               = "builds-reports-jenkins-io"
  storage_account_id = azurerm_storage_account.reports_jenkins_io.id
  # Less than 50Mb of files
  quota = 1
}
resource "azurerm_user_assigned_identity" "builds_reports_jenkins_io" {
  location            = azurerm_resource_group.reports_jenkins_io.location
  name                = azurerm_storage_share.builds_reports_jenkins_io.name
  resource_group_name = azurerm_resource_group.reports_jenkins_io.name
}
resource "azurerm_role_assignment" "builds_reports_jenkins_io" {
  scope                = azurerm_storage_account.reports_jenkins_io.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.builds_reports_jenkins_io.principal_id
}
resource "kubernetes_namespace" "builds_reports_jenkins_io" {
  provider = kubernetes.publick8s

  metadata {
    name = azurerm_storage_share.builds_reports_jenkins_io.name
    labels = {
      name = azurerm_storage_share.builds_reports_jenkins_io.name
    }
  }
}
resource "kubernetes_service_account" "builds_reports_jenkins_io" {
  provider = kubernetes.publick8s
  metadata {
    name      = azurerm_storage_share.builds_reports_jenkins_io.name
    namespace = kubernetes_namespace.builds_reports_jenkins_io.metadata[0].name
  }
}
resource "azurerm_federated_identity_credential" "builds_reports_jenkins_io" {
  name                = azurerm_storage_share.builds_reports_jenkins_io.name
  resource_group_name = azurerm_resource_group.reports_jenkins_io.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.publick8s.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.builds_reports_jenkins_io.id
  subject             = "system:serviceaccount:${kubernetes_namespace.builds_reports_jenkins_io.metadata[0].name}:${kubernetes_service_account.builds_reports_jenkins_io.metadata[0].name}"
}
