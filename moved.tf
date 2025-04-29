moved {
  from = azurerm_managed_disk.jenkins_infra_data_sponsorship["jenkins-infra-data"]
  to   = azurerm_managed_disk.jenkins_infra_data_sponsorship
}
moved {
  from = kubernetes_persistent_volume.jenkins_infra_data_sponsorship["jenkins-infra-data"]
  to   = kubernetes_persistent_volume.jenkins_infra_data_sponsorship
}
moved {
  from = kubernetes_persistent_volume_claim.jenkins_infra_data_sponsorship["jenkins-infra-data"]
  to   = kubernetes_persistent_volume_claim.jenkins_infra_data_sponsorship
}
moved {
  from = azurerm_managed_disk.jenkins_release_data_sponsorship["jenkins-release-data"]
  to   = azurerm_managed_disk.jenkins_release_data_sponsorship
}
moved {
  from = kubernetes_persistent_volume.jenkins_release_data_sponsorship["jenkins-release-data"]
  to   = kubernetes_persistent_volume.jenkins_release_data_sponsorship
}
moved {
  from = kubernetes_persistent_volume_claim.jenkins_release_data_sponsorship["jenkins-release-data"]
  to   = kubernetes_persistent_volume_claim.jenkins_release_data_sponsorship
}
