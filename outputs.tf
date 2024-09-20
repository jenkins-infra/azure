resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "artifact-caching-proxy.privatelink.azurecr.io" = {
      "service_ip" = tolist(azurerm_private_dns_a_record.artifact_caching_proxy.records)[0],
    },
    "public_redis" = {
      "service_hostname" = azurerm_redis_cache.public_redis.hostname,
      "service_port"     = azurerm_redis_cache.public_redis.port,
    },
  })
  filename = "${path.module}/jenkins-infra-data-reports/azure.json"
}

## The script <https://github.com/jenkins-infra/charts-secrets/blob/main/config/trusted.ci.jenkins.io/get-uc-sync-zip-credential.sh>
## requires the following output for generating trusted.ci.jenkins.io's Update Center ZIP credentials
## used by https://github.com/jenkins-infra/update-center2 and https://github.com/jenkins-infra/crawler
# From updates.jenkins.io.tf #
output "updates_jenkins_io_storage_account_name" {
  value = azurerm_storage_account.updates_jenkins_io.name
}
output "updates_jenkins_io_content_fileshare_name" {
  value = azurerm_storage_share.updates_jenkins_io.name
}
output "updates_jenkins_io_redirections_fileshare_name" {
  value = azurerm_storage_share.updates_jenkins_io_redirects.name
}
# From trusted.ci.jenkins.io.tf #
output "trustedci_updatesjenkinsio_content_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.trustedci_updatesjenkinsio_content_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "trustedci_updatesjenkinsio_content_fileshare_serviceprincipal_writer_application_client_secret" {
  sensitive = true
  value     = module.trustedci_updatesjenkinsio_content_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}
output "trustedci_updatesjenkinsio_redirections_fileshare_serviceprincipal_writer_application_client_id" {
  value = module.trustedci_updatesjenkinsio_redirections_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_id
}
output "trustedci_updatesjenkinsio_redirections_fileshare_serviceprincipal_writer_application_client_secret" {
  sensitive = true
  value     = module.trustedci_updatesjenkinsio_redirections_fileshare_serviceprincipal_writer.fileshare_serviceprincipal_writer_application_client_password
}
## End
