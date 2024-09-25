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
        "share_name" = azurerm_storage_share.updates_jenkins_io_content.name,
        "share_uri"  = "/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_content.metadata[0].name,
      },
      "redirections-unsecured" = {
        "share_name" = azurerm_storage_share.updates_jenkins_io_redirects.name
        "share_uri"  = "/unsecured/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_redirects.metadata[0].name,
      },
      "redirections-secured" = {
        "share_name" = azurerm_storage_share.updates_jenkins_io_redirects.name
        "share_uri"  = "/secured/",
        "pvc_name"   = kubernetes_persistent_volume_claim.updates_jenkins_io_redirects.metadata[0].name,
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

## The script <https://github.com/jenkins-infra/charts-secrets/blob/main/config/trusted.ci.jenkins.io/get-uc-sync-zip-credential.sh>
## requires the following output for generating trusted.ci.jenkins.io's Update Center ZIP credentials
## used by https://github.com/jenkins-infra/update-center2 and https://github.com/jenkins-infra/crawler
output "trusted_ci_jenkins_io_updatesjenkinsio_credentials" {
  sensitive = true
  value = jsonencode({
    "storage_name" = azurerm_storage_account.updates_jenkins_io.name,
    "content" = {
      "azure_client_id"       = module.trustedci_updatesjenkinsio_content_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id,
      "azure_client_password" = module.trustedci_updatesjenkinsio_content_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password,
    },
    "redirections-unsecured" = {
      "azure_client_id"       = module.trustedci_updatesjenkinsio_redirects_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id,
      "azure_client_password" = module.trustedci_updatesjenkinsio_redirects_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password,
    },
    "redirections-secured" = {
      "azure_client_id"       = module.trustedci_updatesjenkinsio_redirects_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id,
      "azure_client_password" = module.trustedci_updatesjenkinsio_redirects_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password,
    },
  })
}
