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
  })
  filename = "${path.module}/jenkins-infra-data-reports/azure.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
