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
    dduportal   = "85.27.58.68"
    lemeurherve = "176.185.227.180"
    smerle33    = "82.64.5.129"
    dduportal-2 = "91.182.56.152"
  }

  external_services = {
    "puppet.jenkins.io" = azurerm_public_ip.puppet_jenkins_io.ip_address
  }

  privatek8s_outbound_ip_cidr = "20.96.66.246/32"

  default_tags = {
    scope      = "terraform-managed"
    repository = "jenkins-infra/azure"
  }

  admin_username = "jenkins-infra-team"
}
