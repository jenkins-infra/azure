#
# This terraform plan defines the resources necessary to host repo.jenkins-ci.org proxy cache files
#
# See: https://issues.jenkins-ci.org/browse/INFRA-1176

resource "azurerm_resource_group" "proxy" {
    name     = "${var.prefix}proxy"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "proxy" {
    name                = "${var.prefix}jenkinsproxy"
    resource_group_name = "${azurerm_resource_group.proxy.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
    depends_on          = ["azurerm_resource_group.proxy"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_share" "repo" {
    name = "repo"
    resource_group_name     = "${azurerm_resource_group.proxy.name}"
    storage_account_name    = "${azurerm_storage_account.proxy.name}"
    quota                   = 200
    depends_on              = ["azurerm_resource_group.proxy","azurerm_storage_account.proxy"]
}
