#
# This terraform plan defines the resources necessary to host the Jenkins
# project's reports host.
#
# See: https://issues.jenkins-ci.org/browse/INFRA-947

resource "azurerm_resource_group" "reports" {
    name     = "${var.prefix}-reports"
    location = "${var.location}"
}

resource "azurerm_storage_account" "reports" {
    name                = "${var.prefix}jenkinsreports"
    resource_group_name = "${azurerm_resource_group.reports.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
}

resource "azurerm_storage_container" "reports" {
    name                  = "reports"
    resource_group_name   = "${azurerm_resource_group.reports.name}"
    storage_account_name  = "${azurerm_storage_account.reports.name}"
    container_access_type = "container"
}
