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
