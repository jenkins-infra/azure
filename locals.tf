locals {
  public_pgsql_admin_login = "psqladmin${random_password.pgsql_admin_login.result}"

  shared_galleries = {
    "dev" = {
      description = "Shared images built by pull requests in jenkins-infra/packer-images (consider it untrusted)."
      rg_location = "eastus"
      images_location = {
        "ubuntu-20"    = "eastus"
        "ubuntu-20.04" = "eastus"
        "windows-2019" = "eastus"
        "windows-2022" = "eastus"
      }
    }
    "staging" = {
      description = "Shared images built by the principal code branch in jenkins-infra/packer-images (ready to be tested)."
      rg_location = "eastus"
      images_location = {
        "ubuntu-20"    = "eastus2"
        "ubuntu-20.04" = "eastus"
        "windows-2019" = "eastus2"
        "windows-2022" = "eastus"
      }
    }
    "prod" = {
      description = "Shared images built by the releases in jenkins-infra/packer-images (⚠️ Used in production.)."
      rg_location = "eastus2"
      images_location = {
        "ubuntu-20"    = "eastus2"
        "ubuntu-20.04" = "eastus"
        "windows-2019" = "eastus"
        "windows-2022" = "eastus"
      }
    }
  }

  default_tags = {
    scope      = "terraform-managed"
    repository = "jenkins-infra/azure"
  }
}
