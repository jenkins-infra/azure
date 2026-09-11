## Kubernetes 2.X -> 3.X - Migration file
# Inspired by https://github.com/hashicorp/terraform-provider-kubernetes/issues/2812#issuecomment-3733845983

removed {
  from = module.privatek8s_sponsored_admin_sa.kubernetes_cluster_role_binding.infraciadmin_clusteradmin
  lifecycle {
    destroy = false
  }
}
import {
  id = "infraciadmin_clusteradmin"
  to = module.privatek8s_sponsored_admin_sa.kubernetes_cluster_role_binding_v1.infraciadmin_clusteradmin
}

removed {
  from = module.publick8s_admin_sa.kubernetes_cluster_role_binding.infraciadmin_clusteradmin
  lifecycle {
    destroy = false
  }
}
import {
  id = "infraciadmin_clusteradmin"
  to = module.publick8s_admin_sa.kubernetes_cluster_role_binding_v1.infraciadmin_clusteradmin
}


removed {
  from = module.infracijenkinsio_agents_1_admin_sa.kubernetes_cluster_role_binding.infraciadmin_clusteradmin
  lifecycle {
    destroy = false
  }
}
import {
  id = "infraciadmin_clusteradmin"
  to = module.infracijenkinsio_agents_1_admin_sa.kubernetes_cluster_role_binding_v1.infraciadmin_clusteradmin
}

removed {
  from = kubernetes_namespace.privatek8s_sponsored
  lifecycle {
    destroy = false
  }
}
import {
  for_each = toset(["release-ci-jenkins-io", "infra-ci-jenkins-io", "release-ci-jenkins-io-agents", "data-storage-jenkins-io"])

  id = each.key
  to = kubernetes_namespace_v1.privatek8s_sponsored[each.key]
}

removed {
  from = kubernetes_namespace.publick8s_namespaces
  lifecycle {
    destroy = false
  }
}
import {
  for_each = toset(sort(distinct(concat(
    [for key, value in local.aks_clusters["publick8s"].azurefile_volumes : lookup(value, "pvc_namespace", key)],
    [for key, value in local.aks_clusters["publick8s"].azuredisk_volumes : lookup(value, "pvc_namespace", key)],
    ["data-storage-jenkins-io"],
  ))))

  id = each.key
  to = kubernetes_namespace_v1.publick8s_namespaces[each.key]
}

removed {
  from = kubernetes_namespace.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents
  lifecycle {
    destroy = false
  }
}
import {
  id = "jenkins-infra-agents"
  to = kubernetes_namespace_v1.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents
}

removed {
  from = kubernetes_storage_class.privatek8s_sponsored_statically_provisioned
  lifecycle {
    destroy = false
  }
}
import {
  id = "statically-provisioned"
  to = kubernetes_storage_class_v1.privatek8s_sponsored_statically_provisioned
}

removed {
  from = kubernetes_storage_class.publick8s_statically_provisioned
  lifecycle {
    destroy = false
  }
}
import {
  id = "statically-provisioned"
  to = kubernetes_storage_class_v1.publick8s_statically_provisioned
}

removed {
  from = kubernetes_service_account.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents
  lifecycle {
    destroy = false
  }
}
import {
  id = "jenkins-infra-agents/jenkins-infra-agent"
  to = kubernetes_service_account_v1.infracijenkinsio_agents_1_infra_ci_jenkins_io_agents
}

removed {
  from = kubernetes_service_account.privatek8s_sponsored_infra_ci_jenkins_io_controller
  lifecycle {
    destroy = false
  }
}
import {
  id = "infra-ci-jenkins-io/infra-ci-jenkins-io-controller"
  to = kubernetes_service_account_v1.privatek8s_sponsored_infra_ci_jenkins_io_controller
}

removed {
  from = kubernetes_service_account.privatek8s_sponsored_release_ci_jenkins_io_controller
  lifecycle {
    destroy = false
  }
}
import {
  id = "release-ci-jenkins-io/release-ci-jenkins-io-controller"
  to = kubernetes_service_account_v1.privatek8s_sponsored_release_ci_jenkins_io_controller
}

removed {
  from = kubernetes_service_account.privatek8s_sponsored_release_ci_jenkins_io_agents
  lifecycle {
    destroy = false
  }
}
import {
  id = "release-ci-jenkins-io-agents/release-ci-jenkins-io-agents"
  to = kubernetes_service_account_v1.privatek8s_sponsored_release_ci_jenkins_io_agents
}

removed {
  from = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage
  lifecycle {
    destroy = false
  }
}
import {
  id = "release-ci-jenkins-io-agents-data-storage"
  to = kubernetes_persistent_volume_v1.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage
}

removed {
  from = kubernetes_persistent_volume.privatek8s_sponsored_infra_ci_jenkins_io_data
  lifecycle {
    destroy = false
  }
}
import {
  id = "infra-ci-jenkins-io-data"
  to = kubernetes_persistent_volume_v1.privatek8s_sponsored_infra_ci_jenkins_io_data
}

removed {
  from = kubernetes_persistent_volume.privatek8s_sponsored_release_ci_jenkins_io_data
  lifecycle {
    destroy = false
  }
}
import {
  id = "release-ci-jenkins-io-data"
  to = kubernetes_persistent_volume_v1.privatek8s_sponsored_release_ci_jenkins_io_data
}

removed {
  from = kubernetes_persistent_volume.publick8s_azurefiles
  lifecycle {
    destroy = false
  }
}
import {
  for_each = local.aks_clusters["publick8s"].azurefile_volumes

  id = each.key
  to = kubernetes_persistent_volume_v1.publick8s_azurefiles[each.key]
}

removed {
  from = kubernetes_persistent_volume.publick8s_datadisks
  lifecycle {
    destroy = false
  }
}
import {
  for_each = local.aks_clusters["publick8s"].azuredisk_volumes

  id = element(split("/", each.value.disk_id), "-1")
  to = kubernetes_persistent_volume_v1.publick8s_datadisks[each.key]
}

removed {
  from = kubernetes_persistent_volume_claim.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage
  lifecycle {
    destroy = false
  }
}
import {
  id = "release-ci-jenkins-io-agents/data-storage-jenkins-io"
  to = kubernetes_persistent_volume_claim_v1.privatek8s_sponsored_release_ci_jenkins_io_agents_data_storage
}

removed {
  from = kubernetes_persistent_volume_claim.privatek8s_sponsored_infra_ci_jenkins_io_data
  lifecycle {
    destroy = false
  }
}
import {
  id = "infra-ci-jenkins-io/infra-ci-jenkins-io-data"
  to = kubernetes_persistent_volume_claim_v1.privatek8s_sponsored_infra_ci_jenkins_io_data
}

removed {
  from = kubernetes_persistent_volume_claim.privatek8s_sponsored_release_ci_jenkins_io_data
  lifecycle {
    destroy = false
  }
}
import {
  id = "release-ci-jenkins-io/release-ci-jenkins-io-data"
  to = kubernetes_persistent_volume_claim_v1.privatek8s_sponsored_release_ci_jenkins_io_data
}

removed {
  from = kubernetes_persistent_volume_claim.publick8s_azurefiles
  lifecycle {
    destroy = false
  }
}
import {
  for_each = local.aks_clusters["publick8s"].azurefile_volumes
  id       = "${lookup(each.value, "pvc_namespace", each.key)}/${kubernetes_persistent_volume_v1.publick8s_azurefiles[each.key].metadata[0].name}"
  to       = kubernetes_persistent_volume_claim_v1.publick8s_azurefiles[each.key]
}

removed {
  from = kubernetes_persistent_volume_claim.publick8s_datadisks
  lifecycle {
    destroy = false
  }
}
import {
  for_each = local.aks_clusters["publick8s"].azuredisk_volumes
  id       = "${lookup(each.value, "pvc_namespace", each.key)}/${element(split("/", each.value.disk_id), "-1")}"
  to       = kubernetes_persistent_volume_claim_v1.publick8s_datadisks[each.key]
}
