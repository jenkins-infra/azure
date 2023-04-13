locals {
  public_pgsql_admin_login = "psqladmin${random_password.pgsql_admin_login.result}"

  shared_galleries = {
    "dev" = {
      description = "Shared images built by pull requests in jenkins-infra/packer-images (consider it untrusted)."
      rg_location = "eastus"
      images_location = {
        "ubuntu-20"          = "eastus"
        "ubuntu-20.04"       = "eastus"
        "ubuntu-20.04-amd64" = "eastus"
        "ubuntu-20.04-arm64" = "eastus"
        "ubuntu-22.04-amd64" = "eastus"
        "ubuntu-22.04-arm64" = "eastus"
        "windows-2019"       = "eastus"
        "windows-2019-amd64" = "eastus"
        "windows-2019-arm64" = "eastus"
        "windows-2022"       = "eastus"
        "windows-2022-amd64" = "eastus"
        "windows-2022-arm64" = "eastus"
      }
    }
    "staging" = {
      description = "Shared images built by the principal code branch in jenkins-infra/packer-images (ready to be tested)."
      rg_location = "eastus"
      images_location = {
        "ubuntu-20"          = "eastus2"
        "ubuntu-20.04"       = "eastus"
        "ubuntu-20.04-amd64" = "eastus"
        "ubuntu-20.04-arm64" = "eastus"
        "ubuntu-22.04-amd64" = "eastus"
        "ubuntu-22.04-arm64" = "eastus"
        "windows-2019"       = "eastus"
        "windows-2019-amd64" = "eastus"
        "windows-2019-arm64" = "eastus"
        "windows-2022"       = "eastus"
        "windows-2022-amd64" = "eastus"
        "windows-2022-arm64" = "eastus"
      }
    }
    "prod" = {
      description = "Shared images built by the releases in jenkins-infra/packer-images (⚠️ Used in production.)."
      rg_location = "eastus2"
      images_location = {
        "ubuntu-20"          = "eastus2"
        "ubuntu-20.04"       = "eastus"
        "ubuntu-20.04-amd64" = "eastus"
        "ubuntu-20.04-arm64" = "eastus"
        "ubuntu-22.04-amd64" = "eastus"
        "ubuntu-22.04-arm64" = "eastus"
        "windows-2019"       = "eastus"
        "windows-2019-amd64" = "eastus"
        "windows-2019-arm64" = "eastus"
        "windows-2022"       = "eastus"
        "windows-2022-amd64" = "eastus"
        "windows-2022-arm64" = "eastus"
      }
    }
  }

  admin_allowed_ips = {
    dduportal   = "85.27.58.68"
    lemeurherve = "176.185.227.180"
    smerle33    = "82.64.5.129"
  }

  privatek8s_outbound_ip_cidr = "20.96.66.246/32"

  default_tags = {
    scope      = "terraform-managed"
    repository = "jenkins-infra/azure"
  }
}
