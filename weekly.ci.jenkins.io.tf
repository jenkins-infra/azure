resource "kubernetes_persistent_volume_claim" "jenkins_weekly_data" {
  metadata {
    name = "jenkins-weekly-data"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "managed-csi-premium-zrs-retain"
    volume_mode        = "Filesystem"
    resources {
      requests = {
        storage = "8Gi"
      }
    }
  }
}
