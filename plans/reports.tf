#
# This terraform plan defines the resources necessary to host the Jenkins
# project's reports host.
#
# See: https://issues.jenkins-ci.org/browse/INFRA-947

resource "azurerm_resource_group" "reports" {
    name     = "${var.prefix}-reports"
    location = "${var.location}"
}

#
# Because the argument 'custom_domain' expects a valide CNAME 'custom_domain' set to <storage_account_name>.blob.core.windows.net and
# we don't have it for non production environment.
# And also because Terraform doesn't provide a conditionnal syntax, we choose to create two different storage account', 'report' and 'custom_reports'
# depending on the environment
#

resource "azurerm_storage_account" "custom_reports" {
    count                    = "${ var.prefix == "prod" ? 1 : 0 }"
    name                     = "${var.prefix}jenkinsreports"
    resource_group_name      = "${azurerm_resource_group.reports.name}"

    location                 = "${var.location}"
    account_tier             = "Standard"
    account_replication_type = "GRS"

    custom_domain {
        name = "reports.jenkins.io"
    }
}

resource "azurerm_storage_account" "reports" {
    count                    = "${ var.prefix == "prod" ? 0 : 1 }"
    name                     = "${var.prefix}jenkinsreports"
    resource_group_name      = "${azurerm_resource_group.reports.name}"

    location                 = "${var.location}"
    account_tier             = "Standard"
    account_replication_type = "GRS"
}

resource "azurerm_storage_container" "reports" {
    name                  = "reports"
    resource_group_name   = "${azurerm_resource_group.reports.name}"
    storage_account_name  = "${var.prefix}jenkinsreports"
    container_access_type = "container"
}
