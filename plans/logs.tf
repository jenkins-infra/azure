resource "azurerm_resource_group" "logs" {
    name     = "${var.prefix}logs"
    location = "${var.logslocation}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "logs" {
    name                = "${var.prefix}logs"
    resource_group_name = "${azurerm_resource_group.logs.name}"
    location            = "${var.logslocation}"
    account_type        = "Standard_GRS"
    depends_on          = ["azurerm_resource_group.logs"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_template_deployment" "logs"{
    name  = "${var.prefix}logs"
    resource_group_name = "${ azurerm_resource_group.logs.name }"
    depends_on          = ["azurerm_resource_group.logs"]
    parameters = {
        omsWorkspaceName = "${var.prefix}logs"
        omsRegion = "${var.logslocation}"
        existingStorageAccountName = "${azurerm_storage_account.logs.name}"
        existingStorageAccountResourceGroupName = "${azurerm_resource_group.logs.name}"
        table = "WADWindowsEventLogsTable"
    }
    deployment_mode = "Incremental"
    template_body = "${file("./arm_templates/logs.json")}"
}
