resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "cert.ci.jenkins.io" = {
      "agents_azure_vms" = {
        "resource_group_name"         = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_resource_group_name,
        "network_resource_group_name" = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_network_rg_name,
        "virtual_network_name"        = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_network_name,
        "sub_network_name"            = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_subnet_name,
        "storage_account_name"        = module.cert_ci_jenkins_io_azurevm_agents.ephemeral_agents_storage_account_name,
        "user_assigned_identity"      = azurerm_user_assigned_identity.cert_ci_jenkins_io_jenkins_agents.id,
      },
    },
    "infra.ci.jenkins.io" = {
      "controller_namespace"       = kubernetes_namespace.privatek8s["infra-ci-jenkins-io"].metadata[0].name,
      "controller_service_account" = kubernetes_service_account.privatek8s_infra_ci_jenkins_io_controller.metadata[0].name,
      "controller_pvc"             = kubernetes_persistent_volume_claim.privatek8s_infra_ci_jenkins_io_data.metadata[0].name,
      "agents_azure_vms" = {
        "resource_group_name"         = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_resource_group_name,
        "network_resource_group_name" = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_network_rg_name,
        "virtual_network_name"        = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_network_name,
        "sub_network_name"            = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_subnet_name,
        "storage_account_name"        = module.infra_ci_jenkins_io_azurevm_agents.ephemeral_agents_storage_account_name,
        "user_assigned_identity"      = azurerm_user_assigned_identity.infra_ci_jenkins_io_agents.id,
      },
      "agents_kubernetes_clusters" = {
        "infracijenkinsio_agents_2" = {
          "hostname"           = local.aks_clusters_outputs.infracijenkinsio_agents_2.cluster_hostname
          "kubernetes_version" = local.aks_clusters["infracijenkinsio_agents_2"].kubernetes_version
          "agents_namespaces" = {
            "${kubernetes_namespace.infracijenkinsio_agents_2_infra_ci_jenkins_io_agents.metadata[0].name}" = {
              pods_quota = 150,
            },
          },
          "agents_service_account" = kubernetes_service_account.infracijenkinsio_agents_2_infra_ci_jenkins_io_agents.metadata[0].name,
        },
      },
    },
    "release.ci.jenkins.io" = {
      "controller_namespace"       = kubernetes_namespace.privatek8s["release-ci-jenkins-io"].metadata[0].name,
      "controller_service_account" = kubernetes_service_account.privatek8s_release_ci_jenkins_io_controller.metadata[0].name,
      "controller_pvc"             = kubernetes_persistent_volume_claim.privatek8s_release_ci_jenkins_io_data.metadata[0].name,
      "agents_kubernetes_clusters" = {
        "privatek8s" = {
          "agents_service_account" = kubernetes_service_account.privatek8s_release_ci_jenkins_io_agents.metadata[0].name,
        }
      }
    },
    "trusted.ci.jenkins.io" = {
      "agents_azure_vms" = {
        "resource_group_name"         = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_resource_group_name,
        "network_resource_group_name" = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_network_rg_name,
        "virtual_network_name"        = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_network_name,
        "sub_network_name"            = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_subnet_name,
        "storage_account_name"        = module.trusted_ci_jenkins_io_azurevm_agents.ephemeral_agents_storage_account_name,
        "user_assigned_identity"      = azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins.id,
      },
    },
    "updates.jenkins.io" = {
      "content" = {
        "share_name" = azurerm_storage_share.updates_jenkins_io_data.name,
        "share_uri"  = "/content/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_data.metadata[0].name,
      },
      "redirections" = {
        "share_name" = azurerm_storage_share.updates_jenkins_io_data.name
        "share_uri"  = "/redirections/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_data.metadata[0].name,
      },
      "geoip_data" = {
        "share_name" = azurerm_storage_share.geoip_data.name
        "share_uri"  = "/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_geoipdata.metadata[0].name,
      }
    },
    "ldap.jenkins.io" = {
      "data" = {
        "pvc_name" = kubernetes_persistent_volume_claim.ldap_jenkins_io_data.metadata[0].name,
      },
      "backup" = {
        "pvc_name" = kubernetes_persistent_volume_claim.ldap_jenkins_io_backup.metadata[0].name,
      },
    },
    "puppet.jenkins.io" = {
      "ipv4" = azurerm_public_ip.puppet_jenkins_io.ip_address,
      # DMZ: same in and out public IP
      "outbound_ips" = azurerm_public_ip.puppet_jenkins_io.ip_address,
    },
    "publick8s" = {
      hostname           = data.azurerm_kubernetes_cluster.publick8s.fqdn,
      kubernetes_version = local.aks_clusters["publick8s"].kubernetes_version
      pod_cidrs          = concat(flatten(azurerm_kubernetes_cluster.publick8s.network_profile[*].pod_cidrs)),
      lb_outbound_ips = {
        "ipv4" = [for id, pip in data.azurerm_public_ip.publick8s_lb_outbound : pip.ip_address if can(cidrnetmask("${pip.ip_address}/32"))],
        "ipv6" = [for id, pip in data.azurerm_public_ip.publick8s_lb_outbound : pip.ip_address if !can(cidrnetmask("${pip.ip_address}/32"))],
      },
    },
    "privatek8s" = {
      hostname           = local.aks_clusters_outputs.privatek8s.cluster_hostname,
      kubernetes_version = local.aks_clusters["privatek8s"].kubernetes_version,
      # Outbound IPs are in azure-net (NAT gateway outbound IPs
      public_inbound_lb = {
        "public_ip_name"    = azurerm_public_ip.privatek8s.name,
        "public_ip_rg_name" = azurerm_public_ip.privatek8s.resource_group_name,
        "subnet"            = data.azurerm_subnet.privatek8s_tier.name,
      }
      private_inbound_ips = {
        "ipv4" = azurerm_dns_a_record.privatek8s_private.records,
      }
    },
  })
  filename = "${path.module}/jenkins-infra-data-reports/azure.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}

# infra.ci Azure storage credentials
output "infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_pluginsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}
output "infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_contributorsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}
output "infraci_docsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_docsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_docsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_docsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}
output "infraci_statsjenkinsio_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.infraci_statsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "infraci_statsjenkinsio_fileshare_serviceprincipal_writer_application_client_password" {
  sensitive = true
  value     = module.infraci_statsjenkinsio_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}
