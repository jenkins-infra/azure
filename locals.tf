# Retrieving end dates from updatecli values, easier location to track and update them
data "local_file" "locals_yaml" {
  filename = "updatecli/values.yaml"
}

locals {
  subscription_main      = "dff2ec18-6a8e-405c-8e45-b7df7465acf0"
  subscription_sponsored = "1311c09f-aee0-4d6c-99a4-392c2b543204"

  public_db_pgsql_admin_login = "psqladmin${random_password.public_db_pgsql_admin_login.result}"
  public_db_mysql_admin_login = "mysqladmin${random_password.public_db_mysql_admin_login.result}"

  shared_galleries = {
    "dev" = {
      description = "Shared images built by pull requests in jenkins-infra/packer-images (consider it untrusted)."
      images      = ["ubuntu-22.04-amd64", "ubuntu-22.04-arm64", "windows-2019-amd64", "windows-2022-amd64"]
    }
    "staging" = {
      description = "Shared images built by the principal code branch in jenkins-infra/packer-images (ready to be tested)."
      images      = ["ubuntu-22.04-amd64", "ubuntu-22.04-arm64", "windows-2019-amd64", "windows-2022-amd64"]
    }
    "prod" = {
      description = "Shared images built by the releases in jenkins-infra/packer-images (⚠️ Used in production.)."
      images      = ["ubuntu-22.04-amd64", "ubuntu-22.04-arm64", "windows-2019-amd64", "windows-2022-amd64"]
    }
  }

  external_services = {
    "updates.jenkins.io" = "52.202.51.185"
    "s390x.jenkins.io"   = "148.100.84.76"
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

  kubernetes_versions = {
    "cijenkinsio_agents_1"      = "1.28.9"
    "infracijenkinsio_agents_1" = "1.28.9"
    "privatek8s"                = "1.28.9"
    "publick8s"                 = "1.27.9"
  }

  ci_jenkins_io_fqdn                 = "ci.jenkins.io"
  cijenkinsio_agents_1_compute_zones = [1]
  ci_jenkins_io_agents_1_pod_cidr    = "10.100.0.0/14" # 10.100.0.1 - 10.103.255.255

  infracijenkinsio_agents_1_compute_zones = [1]
  infraci_jenkins_io_agents_1_pod_cidr    = "10.100.0.0/14" # 10.100.0.1 - 10.103.255.255

  publick8s_compute_zones = [3]

  weekly_ci_disk_size    = 8
  weekly_ci_access_modes = ["ReadWriteOnce"]

  end_dates = yamldecode(data.local_file.locals_yaml.content).end_dates
}
