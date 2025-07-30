resource "azurerm_resource_group" "privatek8s_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = "privatek8s-sponsorship"
  location = var.location
  tags     = local.default_tags
}

#trivy:ignore:azure-container-logging #trivy:ignore:azure-container-limit-authorized-ips
resource "azurerm_kubernetes_cluster" "privatek8s_sponsorship" {
  provider = azurerm.jenkins-sponsorship
  name     = local.aks_clusters["privatek8s_sponsorship"].name
  sku_tier = "Standard"
  ## Private cluster requires network setup to allow API access from:
  # - infra.ci.jenkins.io agents (for both terraform job agents and kubernetes-management agents)
  # - private.vpn.jenkins.io to allow admin management (either Azure UI or kube tools from admin machines)
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = true
  dns_prefix                          = local.aks_clusters["privatek8s_sponsorship"].name
  location                            = azurerm_resource_group.privatek8s_sponsorship.location
  resource_group_name                 = azurerm_resource_group.privatek8s_sponsorship.name
  kubernetes_version                  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  # default value but made explicit to please trivy
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  image_cleaner_interval_hours = 48

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard" # Required to customize the outbound type
    pod_cidr            = local.aks_clusters.privatek8s_sponsorship.pod_cidr
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "syspool"
    only_critical_addons_enabled = true                # This property is the only valid way to add the "CriticalAddonsOnly=true:NoSchedule" taint to the default node pool
    vm_size                      = "Standard_D2ads_v5" # At least 2 vCPUS as per AKS best practises

    temporary_name_for_rotation = "syspooltemp"
    upgrade_settings {
      max_surge = "10%"
    }
    os_sku               = "AzureLinux"
    os_disk_type         = "Ephemeral"
    os_disk_size_gb      = 75 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv5-series?tabs=sizestoragelocal (depends on the instance size)
    orchestrator_version = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
    kubelet_disk_type    = "OS"
    auto_scaling_enabled = true
    min_count            = 2 # for best practices
    max_count            = 3 # for upgrade
    vnet_subnet_id       = data.azurerm_subnet.privatek8s_sponsorship_tier.id
    tags                 = local.default_tags
    zones                = [1, 2] # Many zones to ensure it is always able to provide machines in the region. Note: Zone 3 is not allowed for system pool.
  }

  tags = local.default_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "privatek8s_sponsorship_linuxpool" {
  provider = azurerm.jenkins-sponsorship
  name     = "linuxpool"
  vm_size  = "Standard_D4ads_v5"
  upgrade_settings {
    max_surge = "10%"
  }
  os_disk_type          = "Ephemeral"
  os_sku                = "AzureLinux"
  os_disk_size_gb       = 150 # Ref. Cache storage size at https://learn.microsoft.com/fr-fr/azure/virtual-machines/sizes/general-purpose/dadsv5-series?tabs=sizestoragelocal (depends on the instance size)
  orchestrator_version  = local.aks_clusters["privatek8s_sponsorship"].kubernetes_version
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privatek8s_sponsorship.id
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 3
  zones                 = [1, 2]
  vnet_subnet_id        = data.azurerm_subnet.privatek8s_sponsorship_tier.id

  lifecycle {
    ignore_changes = [node_count]
  }

  tags = local.default_tags
}

# Allow cluster to manage network resources in the privatek8s_sponsorship_tier subnet
# It is used for managing the LBs of the public and private ingress controllers
resource "azurerm_role_assignment" "privatek8s_sponsorship_subnets_networkcontributor" {
  for_each = toset([
    data.azurerm_subnet.privatek8s_sponsorship_tier.id,
  ])

  provider                         = azurerm.jenkins-sponsorship
  scope                            = each.key
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Allow cluster to manage the public IP privatek8s_sponsorship
# It is used for managing the public IP of the LB of the public ingress controller
resource "azurerm_role_assignment" "privatek8s_sponsorship_publicip_networkcontributor" {
  provider                         = azurerm.jenkins-sponsorship
  scope                            = azurerm_public_ip.privatek8s_sponsorship.id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.privatek8s_sponsorship.identity[0].principal_id
  skip_service_principal_aad_check = true
}


# Used later by the load balancer deployed on the cluster
# Use case is to allow incoming webhooks
resource "azurerm_public_ip" "privatek8s_sponsorship" {
  provider            = azurerm.jenkins-sponsorship
  name                = "public-privatek8s"
  resource_group_name = azurerm_resource_group.prod_public_ips_sponsorship.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # Needed to fix the error "PublicIPAndLBSkuDoNotMatch"
  tags                = local.default_tags
}
resource "azurerm_management_lock" "privatek8s_sponsorship_publicip" {
  provider   = azurerm.jenkins-sponsorship
  name       = "public-privatek8s-publicip"
  scope      = azurerm_public_ip.privatek8s_sponsorship.id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a sensitive resource that should not be removed when privatek8s-sponsorship is removed"
}

resource "azurerm_dns_a_record" "privatek8s_sponsorship_public" {
  name                = "public.privatek8s-sponsorship"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records             = [azurerm_public_ip.privatek8s_sponsorship.ip_address]
  tags                = local.default_tags
}

resource "azurerm_dns_a_record" "privatek8s_sponsorship_private" {
  name                = "private.privatek8s-sponsorship"
  zone_name           = data.azurerm_dns_zone.jenkinsio.name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 300
  records = [
    # Let's specify an IP at the end of the range to have low probability of being used
    cidrhost(
      data.azurerm_subnet.privatek8s_sponsorship_tier.address_prefixes[0],
      -2,
    )
  ]
  tags = local.default_tags
}

# Used by all the controller (for their Jenkins Home PVCs)
resource "kubernetes_storage_class" "privatek8s_sponsorship_statically_provisioned" {
  provider = kubernetes.privatek8s_sponsorship
  metadata {
    name = "statically-provisioned"
  }
  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
}

# Configure the jenkins-infra/kubernetes-management admin service account
module "privatek8s_sponsorship_admin_sa" {
  providers = {
    kubernetes = kubernetes.privatek8s_sponsorship
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = azurerm_kubernetes_cluster.privatek8s_sponsorship.name
  cluster_hostname           = local.aks_clusters_outputs.privatek8s_sponsorship.cluster_hostname
  cluster_ca_certificate_b64 = azurerm_kubernetes_cluster.privatek8s_sponsorship.kube_config.0.cluster_ca_certificate
}
output "kubeconfig_management_privatek8s_sponsorship" {
  sensitive = true
  value     = module.privatek8s_sponsorship_admin_sa.kubeconfig
}
