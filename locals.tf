locals {
  public_db_pgsql_admin_login = "psqladmin${random_password.public_db_pgsql_admin_login.result}"

  shared_galleries = {
    "dev" = {
      description = "Shared images built by pull requests in jenkins-infra/packer-images (consider it untrusted)."
      rg_location = "eastus"
      images_location = {
        "ubuntu-22.04-amd64" = "eastus"
        "ubuntu-22.04-arm64" = "eastus"
        "windows-2019-amd64" = "eastus"
        "windows-2022-amd64" = "eastus"
      }
    }
    "staging" = {
      description = "Shared images built by the principal code branch in jenkins-infra/packer-images (ready to be tested)."
      rg_location = "eastus"
      images_location = {
        "ubuntu-22.04-amd64" = "eastus"
        "ubuntu-22.04-arm64" = "eastus"
        "windows-2019-amd64" = "eastus"
        "windows-2022-amd64" = "eastus"
      }
    }
    "prod" = {
      description = "Shared images built by the releases in jenkins-infra/packer-images (⚠️ Used in production.)."
      rg_location = "eastus2"
      images_location = {
        "ubuntu-22.04-amd64" = "eastus"
        "ubuntu-22.04-arm64" = "eastus"
        "windows-2019-amd64" = "eastus"
        "windows-2022-amd64" = "eastus"
      }
    }
  }

  admin_allowed_ips = {
    dduportal     = "85.27.34.43"
    dduportal-2   = "86.202.255.126"
    lemeurherve   = "176.185.227.180"
    lemeurherve-2 = "176.145.123.59"
    smerle33      = "82.64.5.129"
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

  privatek8s_outbound_ip_cidr = "20.96.66.246/32"

  default_tags = {
    scope      = "terraform-managed"
    repository = "jenkins-infra/azure"
  }

  admin_username = "jenkins-infra-team"

  kubernetes_versions = {
    "privatek8s" = "1.25.6"
    "publick8s"  = "1.25.6"
  }
}
