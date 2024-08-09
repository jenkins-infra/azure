resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "artifact-caching-proxy.privatelink.azurecr.io" = {
      "service_ip" = azurerm_private_dns_a_record.artifact_caching_proxy,
    },
  })
  filename = "${path.module}/jenkins-infra-data-reports/azure.json"
}
