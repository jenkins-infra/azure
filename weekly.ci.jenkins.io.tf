resource "kubernetes_persistent_volume_claim" "jenkins_weekly_PVC" {
  metadata {
    name = "jenkins-weekly-pvc"
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
