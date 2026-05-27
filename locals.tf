# Retrieving end dates from updatecli values, easier location to track and update them
data "local_file" "locals_yaml" {
  filename = "updatecli/values.yaml"
}

locals {
  public_db_pgsql_admin_login = "psqladmin${random_password.public_db_pgsql_admin_login.result}"

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

  admin_public_ips = {
    dduportal = ["82.67.112.167"],
    smerle33  = ["86.207.165.174"],
    mwaite    = ["162.142.59.220"],
    hlemeur   = ["82.67.38.76"],
  }

  # TODO: track with updatecli
  external_services = {
    "archives.jenkins.io" = "46.101.121.132",
  }

  # Ref. https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses
  # Only IPv4
  github_ips = {
    webhooks = ["140.82.112.0/20", "143.55.64.0/20", "185.199.108.0/22", "192.30.252.0/22"]
    # Define GitHub IPs as a string in locals block (easier to track with updatecli)
    scm = "192.30.252.0/22 185.199.108.0/22 140.82.112.0/20 143.55.64.0/20 2a0a:a440::/29 2606:50c0::/32 20.201.28.151/32 20.205.243.166/32 20.87.245.0/32 4.237.22.38/32 4.228.31.150/32 20.207.73.82/32 20.27.177.113/32 20.200.245.247/32 20.175.192.147/32 20.233.83.145/32 20.29.134.23/32 20.199.39.232/32 20.217.135.5/32 4.225.11.194/32 4.208.26.197/32 20.26.156.215/32 20.201.28.152/32 20.205.243.160/32 20.87.245.4/32 4.237.22.40/32 4.228.31.145/32 20.207.73.83/32 20.27.177.118/32 20.200.245.248/32 20.175.192.146/32 20.233.83.149/32 20.29.134.19/32 20.199.39.227/32 20.217.135.4/32 4.225.11.200/32 4.208.26.198/32 20.26.156.214/32"
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
    "infracijenkinsio_agents_1" = {
      name               = "infracijenkinsio-agents-1",
      kubernetes_version = "1.33.5",
      # https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay#pods
      pod_cidr = "10.100.0.0/14", # 10.100.0.1 - 10.103.255.255
    },
    "privatek8s-sponsored" = {
      name               = "privatek8s-sponsored",
      kubernetes_version = "1.33.11",
      # https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay#pods
      pod_cidr = "10.100.0.0/14", # 10.100.0.1 - 10.103.255.255
    },
    "publick8s" = {
      name               = "publick8s",
      kubernetes_version = "1.33.5",
      # https://learn.microsoft.com/en-us/azure/aks/concepts-network-azure-cni-overlay#pods
      pod_cidrs = [
        "10.100.0.0/14",       # 10.100.0.1 - 10.103.255.255
        "fd12:3456:789a::/64", # Dual stack is required to provide public IPv6 LBs
      ],
      azurefile_volumes = {
        "get-jenkins-io"                = {},
        "updates-jenkins-io"            = {},
        "www-jenkins-io"                = {},
        "staging-pkg-origin-jenkins-io" = {},
        "staging-get-jenkins-io"        = {},
        "pkg-origin-jenkins-io"         = {},
        "alpha-docs-jenkins-io" = {
          capacity = azurerm_storage_share.docs_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.docs_jenkins_io.resource_group_name}#${azurerm_storage_account.docs_jenkins_io.name}#${azurerm_storage_share.docs_jenkins_io.name}"
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
            resourceGroup = azurerm_storage_account.docs_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.docs_jenkins_io.name,
          },
          secret_name         = azurerm_storage_account.docs_jenkins_io.name,
          secret_namespace    = "alpha-docs-jenkins-io",
          storage_account_key = azurerm_storage_account.docs_jenkins_io.primary_access_key,
        },
        "builds-reports-jenkins-io" = {
          capacity = azurerm_storage_share.builds_reports_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.builds_reports_jenkins_io.resource_group_name}#${azurerm_storage_account.builds_reports_jenkins_io.name}#${azurerm_storage_share.builds_reports_jenkins_io.name}"
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
          secret_name         = azurerm_storage_account.builds_reports_jenkins_io.name,
          secret_namespace    = "builds-reports-jenkins-io",
          storage_account_key = azurerm_storage_account.builds_reports_jenkins_io.primary_access_key,
        },
        "contributors-jenkins-io" = {
          capacity = azurerm_storage_share.contributors_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.contributors_jenkins_io.resource_group_name}#${azurerm_storage_account.contributors_jenkins_io.name}#${azurerm_storage_share.contributors_jenkins_io.name}"
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
            resourceGroup = azurerm_storage_account.contributors_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.contributors_jenkins_io.name,
          },
          secret_name         = azurerm_storage_account.contributors_jenkins_io.name,
          secret_namespace    = "contributors-jenkins-io",
          storage_account_key = azurerm_storage_account.contributors_jenkins_io.primary_access_key,
        },
        "docs-jenkins-io" = {
          capacity = azurerm_storage_share.docs_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.docs_jenkins_io.resource_group_name}#${azurerm_storage_account.docs_jenkins_io.name}#${azurerm_storage_share.docs_jenkins_io.name}"
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
            resourceGroup = azurerm_storage_account.docs_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.docs_jenkins_io.name,
          },
          secret_name         = azurerm_storage_account.docs_jenkins_io.name,
          secret_namespace    = "docs-jenkins-io",
          storage_account_key = azurerm_storage_account.docs_jenkins_io.primary_access_key,
        },
        "javadoc-jenkins-io" = {
          capacity = azurerm_storage_share.javadoc_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.javadoc_jenkins_io.resource_group_name}#${azurerm_storage_account.javadoc_jenkins_io.name}#${azurerm_storage_share.javadoc_jenkins_io.name}"
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
            resourceGroup = azurerm_storage_account.javadoc_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.javadoc_jenkins_io.name,
          },
          secret_name         = azurerm_storage_account.javadoc_jenkins_io.name,
          secret_namespace    = "javadoc-jenkins-io",
          storage_account_key = azurerm_storage_account.javadoc_jenkins_io.primary_access_key,
        },
        # LDAP needs a read/write PVC to store its backups
        "ldap-jenkins-io-backup" = {
          pvc_namespace = "ldap-jenkins-io",
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.ldap_jenkins_io.resource_group_name}#${azurerm_storage_account.ldap_jenkins_io.name}#${azurerm_storage_share.ldap_jenkins_io_backups.name}"
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
            resourceGroup = azurerm_storage_account.ldap_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.ldap_jenkins_io_backups.name,
          },
          secret_name         = azurerm_storage_account.ldap_jenkins_io.name,
          secret_namespace    = "ldap-jenkins-io",
          storage_account_key = azurerm_storage_account.ldap_jenkins_io.primary_access_key,
        },
        "plugins-jenkins-io" = {
          capacity = azurerm_storage_share.plugins_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.plugins_jenkins_io.resource_group_name}#${azurerm_storage_account.plugins_jenkins_io.name}#${azurerm_storage_share.plugins_jenkins_io.name}"
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
            resourceGroup = azurerm_storage_account.plugins_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.plugins_jenkins_io.name,
          },
          secret_name         = azurerm_storage_account.plugins_jenkins_io.name,
          secret_namespace    = "plugins-jenkins-io",
          storage_account_key = azurerm_storage_account.plugins_jenkins_io.primary_access_key,
        },
        "reports-jenkins-io" = {
          capacity = azurerm_storage_share.reports_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.reports_jenkins_io.resource_group_name}#${azurerm_storage_account.reports_jenkins_io.name}#${azurerm_storage_share.reports_jenkins_io.name}"
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
            resourceGroup = azurerm_storage_account.reports_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.reports_jenkins_io.name,
          },
          secret_name         = azurerm_storage_account.reports_jenkins_io.name,
          secret_namespace    = "reports-jenkins-io",
          storage_account_key = azurerm_storage_account.reports_jenkins_io.primary_access_key,
        },
        "stats-jenkins-io" = {
          capacity = azurerm_storage_share.stats_jenkins_io.quota,
          # `volumeHandle` must be unique on the cluster for this volume and must looks like: "{resource-group-name}#{account-name}#{file-share-name}"
          volume_handle = "${azurerm_storage_account.stats_jenkins_io.resource_group_name}#${azurerm_storage_account.stats_jenkins_io.name}#${azurerm_storage_share.stats_jenkins_io.name}"
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
            resourceGroup = azurerm_storage_account.stats_jenkins_io.resource_group_name,
            shareName     = azurerm_storage_share.stats_jenkins_io.name,
          },
          secret_name         = azurerm_storage_account.stats_jenkins_io.name,
          secret_namespace    = "stats-jenkins-io",
          storage_account_key = azurerm_storage_account.stats_jenkins_io.primary_access_key,
        },
      }
      azuredisk_volumes = {
        "ldap-jenkins-io" = {
          disk_id    = "${azurerm_managed_disk.ldap_jenkins_io_data.id}",
          disk_size  = "${azurerm_managed_disk.ldap_jenkins_io_data.disk_size_gb}",
          disk_rg_id = "${azurerm_resource_group.ldap_jenkins_io.id}",
        }
        "weekly-ci-jenkins-io" = {
          disk_id    = "${azurerm_managed_disk.weekly_ci_jenkins_io.id}",
          disk_size  = "${azurerm_managed_disk.weekly_ci_jenkins_io.disk_size_gb}",
          disk_rg_id = "${azurerm_resource_group.weekly_ci_jenkins_io.id}",
        }
      }
    },
    "compute_zones" = {
      system_pool = [1, 2], # Note: Zone 3 is not allowed for system pool.
      arm64_pool  = [2, 3],
      amd64_pool  = [1, 2],
    }
    "compute_zones_sponsored" = {
      system_pool = [1, 2], # Note: Zone 3 is not allowed for system pool.
      arm64_pool  = [1, 2],
      amd64_pool  = [2],
    }
  }

  # These cluster_hostname cannot be on the 'local.aks_cluster' to avoid cyclic dependencies (when expanding the map)
  aks_clusters_outputs = {
    "infracijenkinsio_agents_1" = {
      cluster_hostname = "https://${azurerm_kubernetes_cluster.infracijenkinsio_agents_1.fqdn}:443", # Cannot use the kubeconfig host as it provides a private DNS name
    },
    "privatek8s-sponsored" = {
      cluster_hostname = "https://${azurerm_kubernetes_cluster.privatek8s_sponsored.fqdn}:443", # Cannot use the kubeconfig host as it provides a private DNS name
    },
    "publick8s" = {
      cluster_hostname = "https://${azurerm_kubernetes_cluster.publick8s.fqdn}:443", # Cannot use the kubeconfig host as it provides a private DNS name
    },
  }

  end_dates = yamldecode(data.local_file.locals_yaml.content).end_dates

  app_subnets = {
    "release.ci.jenkins.io" = {
      "controller" = [
        # Sponsored subscription
        data.azurerm_subnet.privatek8s_sponsored_release_ci_jenkins_io_controller.id,
      ],
      "agents" = [
        # Sponsored subscription
        data.azurerm_subnet.privatek8s_sponsored_release_ci_jenkins_io_agents.id,

      ],
    },
    "infra.ci.jenkins.io" = {
      "controller" = [
        # Sponsored subscription
        data.azurerm_subnet.privatek8s_sponsored_infra_ci_jenkins_io_controller.id,
      ],
      "agents" = [
        # VM agents (Jenkins Sponsored subscription)
        data.azurerm_subnet.infra_ci_jenkins_io_sponsored_ephemeral_agents.id,
        # Container agents (Jenkins Sponsored subscription)
        data.azurerm_subnet.infra_ci_jenkins_io_sponsored_kubernetes_agents.id,
      ],
    },
    "trusted.ci.jenkins.io" = {
      "controller" = [data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_controller.id],
      "agents" = [
        # Permanent agents (Update Center generation)
        data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_permanent_agents.id,
        # VM agents (Jenkins Sponsored subscription)
        data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_ephemeral_agents.id,
      ],
    },
  }

  infra_ci_jenkins_io_fqdn                        = "infra.ci.jenkins.io"
  infra_ci_jenkins_io_service_short_name          = trimprefix(trimprefix(local.infra_ci_jenkins_io_fqdn, "jenkins.io"), ".")
  infra_ci_jenkins_io_service_short_stripped_name = replace(local.infra_ci_jenkins_io_service_short_name, ".", "-")
}
