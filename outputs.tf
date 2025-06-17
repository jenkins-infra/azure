resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "artifact-caching-proxy.privatelink.azurecr.io" = {
      "service_ip" = tolist(azurerm_private_dns_a_record.artifact_caching_proxy.records)[0],
    },
    "public_redis" = {
      "service_hostname" = azurerm_redis_cache.public_redis.hostname,
      "service_port"     = azurerm_redis_cache.public_redis.port,
    },
    "updates.jenkins.io" = {
      "content" = {
        "share_name" = azurerm_storage_share.updates_jenkins_io_data.name,
        "share_uri"  = "/content/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_data.metadata[0].name,
      },
      "redirections-unsecured" = {
        "share_name" = azurerm_storage_share.updates_jenkins_io_data.name
        "share_uri"  = "/redirections-unsecured/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_data.metadata[0].name,
      },
      "redirections-secured" = {
        "share_name" = azurerm_storage_share.updates_jenkins_io_data.name
        "share_uri"  = "/redirections-secured/",
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
    "privatek8s_sponsorship" = {
      hostname           = local.aks_clusters_outputs.privatek8s_sponsorship.cluster_hostname,
      kubernetes_version = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version,
      # Outbound IPs are in azure-net (NAT gateway outbound IPs
      public_inbound_lb = {
        "public_ip_name"    = azurerm_public_ip.privatek8s_sponsorship.name,
        "public_ip_rg_name" = azurerm_public_ip.privatek8s_sponsorship.resource_group_name,
        "subnet"            = data.azurerm_subnet.privatek8s_sponsorship_tier.name,
      }
      private_inbound_ips = {
        "ipv4" = azurerm_dns_a_record.privatek8s_sponsorship_private.records,
      }
    },
    "cijenkinsio_agents_1" = {
      hostname           = local.aks_clusters_outputs.cijenkinsio_agents_1.cluster_hostname
      kubernetes_version = local.aks_clusters["cijenkinsio_agents_1"].kubernetes_version
      agent_namespaces   = local.aks_clusters.cijenkinsio_agents_1.agent_namespaces,
      maven_cache_pvcs = merge(
        { for agent_ns, agent_setup in local.aks_clusters.cijenkinsio_agents_1.agent_namespaces :
        agent_ns => kubernetes_persistent_volume_claim.ci_jenkins_io_maven_cache_readonly[agent_ns].metadata[0].name },
        { "${kubernetes_namespace.ci_jenkins_io_maven_cache.metadata[0].name}" = kubernetes_persistent_volume_claim.ci_jenkins_io_maven_cache_write.metadata[0].name },
      ),
    },
    "infracijenkinsio_agents_1" = {
      hostname           = local.aks_clusters_outputs.infracijenkinsio_agents_1.cluster_hostname
      kubernetes_version = local.aks_clusters["infracijenkinsio_agents_1"].kubernetes_version
    },
    "infracijenkinsio_agents_2" = {
      hostname           = local.aks_clusters_outputs.infracijenkinsio_agents_2.cluster_hostname
      kubernetes_version = local.aks_clusters["infracijenkinsio_agents_2"].kubernetes_version
    },
    "azure.ci.jenkins.io" = {
      "service_ips" = {
        "ipv4" = module.ci_jenkins_io_sponsorship.controller_public_ipv4,
        "ipv6" = module.ci_jenkins_io_sponsorship.controller_public_ipv6,
      },
      "azure-vm-agents" = {
        "resource_group_name"         = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_resource_group_name,
        "network_resource_group_name" = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_network_rg_name,
        "virtual_network_name"        = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_network_name,
        "sub_network_name"            = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_subnet_name,
        "storage_account_name"        = module.ci_jenkins_io_azurevm_agents_jenkins_sponsorship.ephemeral_agents_storage_account_name,
      },
    }
  })
  filename = "${path.module}/jenkins-infra-data-reports/azure.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
