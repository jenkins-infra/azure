# Retrieving end dates from updatecli values, easier location to track and update them
data "local_file" "locals_yaml" {
  filename = "updatecli/values.yaml"
}

locals {
  public_db_pgsql_admin_login = "psqladmin${random_password.public_db_pgsql_admin_login.result}"
  public_db_mysql_admin_login = "mysqladmin${random_password.public_db_mysql_admin_login.result}"

  shared_galleries = {
    "dev" = {
      description = "Shared images built by pull requests in jenkins-infra/packer-images (consider it untrusted)."
      images      = ["ubuntu-22.04-amd64", "ubuntu-22.04-arm64", "windows-2019-amd64", "windows-2022-amd64", "windows-2025-amd64"]
    }
    "staging" = {
      description = "Shared images built by the principal code branch in jenkins-infra/packer-images (ready to be tested)."
      images      = ["ubuntu-22.04-amd64", "ubuntu-22.04-arm64", "windows-2019-amd64", "windows-2022-amd64", "windows-2025-amd64"]
    }
    "prod" = {
      description = "Shared images built by the releases in jenkins-infra/packer-images (⚠️ Used in production.)."
      images      = ["ubuntu-22.04-amd64", "ubuntu-22.04-arm64", "windows-2019-amd64", "windows-2022-amd64", "windows-2025-amd64"]
    }
  }

  # Tracked by 'updatecli' from the following source: https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
  outbound_ips_trusted_ci_jenkins_io = "104.209.128.236"
  # Tracked by 'updatecli' from the following source: https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
  outbound_ips_infra_ci_jenkins_io = "20.57.120.46 52.179.141.53 172.210.200.59 20.10.193.4"
  # Tracked by 'updatecli' from the following source: https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
  outbound_ips_private_vpn_jenkins_io = "52.232.183.117"
  # TODO: remove when publick8s will be changed to a "private" cluster
  outbound_ips_publick8s_jenkins_io = [
    "20.22.30.74",  # Outbound IPv4 of the cluster LB
    "20.22.30.9",   # Outbound IPv4 of the cluster LB
    "20.85.71.108", # Outbound IPv4 of the cluster LB
    "20.7.192.189", # Outbound IP of the NAT gateway - https://github.com/jenkins-infra/azure-net/blob/7aa7fc5a8a39dd7bafee0e89c4fffe096692baa8/outputs.tf#L23-L25
  ]

  admin_public_ips = {
    dduportal = ["89.84.210.161"],
    smerle33  = ["82.64.5.129"],
    mwaite    = ["162.142.59.220"],
  }

  # TODO: track with updatecli
  external_services = {
    "pkg.origin.jenkins.io" = "52.202.51.185",
    "archives.jenkins.io"   = "46.101.121.132",
  }

  # Ref. https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses
  # Only IPv4
  github_ips = {
    webhooks = ["140.82.112.0/20", "143.55.64.0/20", "185.199.108.0/22", "192.30.252.0/22"]
  }
  gpg_keyserver_ips = {
    "keyserver.ubuntu.com" = ["162.213.33.8", "162.213.33.9"]
  }

  default_tags = {
    scope      = "terraform-managed"
    repository = "jenkins-infra/azure"
  }

  admin_username = "jenkins-infra-team"

  aks_clusters = {
    "infracijenkinsio_agents_2" = {
      name               = "infracijenkinsio-agents-2",
      kubernetes_version = "1.31.6",
      # https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay#pods
      pod_cidr = "10.100.0.0/14", # 10.100.0.1 - 10.103.255.255
    },
    "privatek8s" = {
      name               = "privatek8s",
      kubernetes_version = "1.31.6",
      # https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay#pods
      pod_cidr = "10.100.0.0/14", # 10.100.0.1 - 10.103.255.255
    },
    "old_publick8s" = {
      name               = "publick8s-${random_pet.suffix_publick8s.id}",
      kubernetes_version = "1.31.6",
      compute_zones      = [3],
    },
    "publick8s" = {
      name               = "publick8s",
      kubernetes_version = "1.32.6",
      # https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay#pods
      pod_cidrs = [
        "10.100.0.0/14",       # 10.100.0.1 - 10.103.255.255
        "fd12:3456:789a::/64", # Dual stack is required to provide public IPv6 LBs
      ],
      azurefile_volumes = {
        "get-jenkins-io"     = {},
        "updates-jenkins-io" = {},
        "javadoc-jenkins-io" = {},
        "www-jenkins-io"     = {},
        ## The service build.reports.jenkins.io is different than other Azure file as all (private) controllers may write to it
        ## As such we do not use the "all in one" NFS unless we change/relax the threat model
        "builds-reports-jenkins-io" = {
          capacity = azurerm_storage_share.builds_reports_jenkins_io.quota,
          mount_options = [
            "dir_mode=0777",
            "file_mode=0777",
            "uid=0",
            "gid=0",
            "mfsymlinks",
            "cache=strict", # Default on usual kernels but worth setting it explicitly
            "nosharesock",  # Use new TCP connection for each CIFS mount (need more memory but avoid lost packets to create mount timeouts)
            "nobrl",        # disable sending byte range lock requests to the server and for applications which have challenges with posix locks
          ],
          volume_attributes = {
            resourceGroup = azurerm_storage_account.builds_reports_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.builds_reports_jenkins_io.name,
          },
          secret_name         = azurerm_storage_share.builds_reports_jenkins_io.name,
          secret_namespace    = "builds-reports-jenkins-io",
          storage_account_key = azurerm_storage_account.builds_reports_jenkins_io.primary_access_key,
        },
        # LDAP needs a read/write PVC to store its backups
        "ldap-jenkins-io-backup" = {
          pvc_namespace = "ldap-jenkins-io",
          # between 3 to 8 years of LDAP ldif backups
          # TODO: We should purge backups older than 1 year (username, email and password data)
          capacity     = "10",
          access_modes = ["ReadWriteMany"],
          read_only    = false,
          mount_options = [
            "dir_mode=0777",
            "file_mode=0777",
            "uid=0",
            "gid=0",
            "mfsymlinks",
            "cache=strict", # Default on usual kernels but worth setting it explicitly
            "nosharesock",  # Use new TCP connection for each CIFS mount (need more memory but avoid lost packets to create mount timeouts)
            "nobrl",        # disable sending byte range lock requests to the server and for applications which have challenges with posix locks
          ]
          volume_attributes = {
            resourceGroup = azurerm_storage_account.ldap_backups.resource_group_name,
            shareName     = azurerm_storage_share.ldap.name,
          },
          secret_name      = "ldap-backup-storage",
          secret_namespace = "ldap-jenkins-io",
        },
      }
      azuredisk_volumes = {
        "ldap-jenkins-io" = {
          disk_name  = "${azurerm_managed_disk.ldap_jenkins_io_data.name}",
          disk_size  = "${azurerm_managed_disk.ldap_jenkins_io_data.disk_size_gb}",
          disk_rg_id = "${azurerm_resource_group.ldap.id}",
        }
        "weekly-ci-jenkins-io" = {
          disk_name  = "${azurerm_managed_disk.jenkins_weekly_data.name}",
          disk_size  = "${azurerm_managed_disk.jenkins_weekly_data.disk_size_gb}",
          disk_rg_id = "${azurerm_resource_group.weekly_ci_controller.id}",
        }
      }
    },
    "compute_zones" = {
      system_pool = [1, 2], # Note: Zone 3 is not allowed for system pool.
      arm64_pool  = [2, 3],
      amd64_pool  = [1, 2],
    }
  }

  # These cluster_hostname cannot be on the 'local.aks_cluster' to avoid cyclic dependencies (when expanding the map)
  aks_clusters_outputs = {
    "infracijenkinsio_agents_2" = {
      cluster_hostname = "https://${azurerm_kubernetes_cluster.infracijenkinsio_agents_2.fqdn}:443", # Cannot use the kubeconfig host as it provides a private DNS name
    },
    "privatek8s" = {
      cluster_hostname = "https://${azurerm_kubernetes_cluster.privatek8s.fqdn}:443", # Cannot use the kubeconfig host as it provides a private DNS name
    },
    "publick8s" = {
      cluster_hostname = "https://${azurerm_kubernetes_cluster.publick8s.fqdn}:443", # Cannot use the kubeconfig host as it provides a private DNS name
    },
  }

  end_dates = yamldecode(data.local_file.locals_yaml.content).end_dates

  app_subnets = {
    "release.ci.jenkins.io" = {
      "controller" = [data.azurerm_subnet.privatek8s_release_ci_controller_tier.id],
      "agents" = [
        # Container agents
        data.azurerm_subnet.privatek8s_release_tier.id,
      ],
    },
    "infra.ci.jenkins.io" = {
      "controller" = [data.azurerm_subnet.privatek8s_infra_ci_controller_tier.id],
      "agents" = [
        # VM agents (CDF subscription)
        data.azurerm_subnet.infra_ci_jenkins_io_ephemeral_agents.id,
        # Container agents (CDF subscription)
        data.azurerm_subnet.infracijenkinsio_agents_2.id,
      ],
    },
    "trusted.ci.jenkins.io" = {
      "controller" = [data.azurerm_subnet.trusted_ci_jenkins_io_controller.id],
      "agents" = [
        # Permanent agents (Update Center generation)
        data.azurerm_subnet.trusted_ci_jenkins_io_permanent_agents.id,
        # VM agents (CDF subscription)
        data.azurerm_subnet.trusted_ci_jenkins_io_ephemeral_agents.id,
      ],
    },
    "cert.ci.jenkins.io" = {
      "controller" = [data.azurerm_subnet.cert_ci_jenkins_io_controller.id],
      "agents" = [
        # VM agents (CDF subscription)
        data.azurerm_subnet.cert_ci_jenkins_io_ephemeral_agents.id,
      ],
    },
  }

  infra_ci_jenkins_io_fqdn                        = "infra.ci.jenkins.io"
  infra_ci_jenkins_io_service_short_name          = trimprefix(trimprefix(local.infra_ci_jenkins_io_fqdn, "jenkins.io"), ".")
  infra_ci_jenkins_io_service_short_stripped_name = replace(local.infra_ci_jenkins_io_service_short_name, ".", "-")
}
