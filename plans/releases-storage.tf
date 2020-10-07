#
# This terraform plan defines the resources necessary to host the Jenkins
# project's core releases via Azure Blob Storage
#
# These resources were originally created manually via the Azure Portal, but
# this plan represents the enforcement of those resources.

resource "azurerm_resource_group" "releases" {
  name     = "${var.prefix}-core-releases"
  location = var.location
}

resource "azurerm_storage_account" "releases" {
  name                     = "${var.prefix}jenkinsreleases"
  resource_group_name      = azurerm_resource_group.releases.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

##
## Defining containers for the various types of Jenkisn releases. This could
## probably be "looped" in some form or fashion using Terraform, but there are few
## enough resources which need to be defined that it would be more difficult to
## maintain and read if it were made more complex than the copy-pasta below.
##

# Containers for the .war file releases:
########################################
resource "azurerm_storage_container" "war" {
  name                  = "war"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "war-stable" {
  name                  = "war-stable"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "war-stable-rc" {
  name                  = "war-stable-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "war-rc" {
  name                  = "war-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

########################################

# Containers for Red Hat rpm releases:
######################################
resource "azurerm_storage_container" "redhat" {
  name                  = "redhat"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "redhat-stable" {
  name                  = "redhat-stable"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "redhat-stable-rc" {
  name                  = "redhat-stable-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "redhat-rc" {
  name                  = "redhat-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

######################################

# Containers for openSUSE rpm releases:
#######################################
resource "azurerm_storage_container" "opensuse" {
  name                  = "opensuse"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "opensuse-stable" {
  name                  = "opensuse-stable"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "opensuse-stable-rc" {
  name                  = "opensuse-stable-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "opensuse-rc" {
  name                  = "opensuse-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

#######################################

# Container for Debian (.dpkg) releases:
########################################
resource "azurerm_storage_container" "debian" {
  name                  = "debian"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "debian-stable" {
  name                  = "debian-stable"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "debian-stable-rc" {
  name                  = "debian-stable-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "debian-rc" {
  name                  = "debian-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

########################################

# Container for Windows (.zip) releases:
########################################
resource "azurerm_storage_container" "windows" {
  name                  = "windows"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "windows-stable" {
  name                  = "windows-stable"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "windows-stable-rc" {
  name                  = "windows-stable-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "windows-rc" {
  name                  = "windows-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

########################################

# Container for Mac OS X (.pkg) releases:
#########################################
resource "azurerm_storage_container" "osx" {
  name                  = "osx"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "osx-stable" {
  name                  = "osx-stable"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "osx-stable-rc" {
  name                  = "osx-stable-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "osx-rc" {
  name                  = "osx-rc"
  storage_account_name  = azurerm_storage_account.releases.name
  container_access_type = "container"
}

#########################################

resource "azurerm_storage_share" "mirrorbits" {
  name                 = "mirrorbits"
  storage_account_name = azurerm_storage_account.releases.name
}

resource "azurerm_storage_share" "archives" {
  name                 = "archives"
  storage_account_name = azurerm_storage_account.releases.name
}

