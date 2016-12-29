resource "azurerm_resource_group" "logs" {
    name     = "${var.prefix}logs"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_account" "logs" {
    name                = "${var.prefix}logs"
    resource_group_name = "${azurerm_resource_group.logs.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
    depends_on          = ["azurerm_resource_group.logs"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_storage_share" "logs" {
    name = "logs"
    resource_group_name     = "${azurerm_resource_group.logs.name}"
    storage_account_name    = "${azurerm_storage_account.logs.name}"
    quota                   = 50
    depends_on              = ["azurerm_resource_group.logs","azurerm_storage_account.logs"]
}

resource "azurerm_template_deployment" "logs"{
    name  = "${var.prefix}logs"
    resource_group_name = "${ azurerm_resource_group.logs.name }"
    depends_on          = ["azurerm_resource_group.logs"]
    parameters = {
        omsWorkspaceName = "${var.prefix}logs"
        omsRegion = "${var.location}"
        existingStorageAccountName = "${azurerm_storage_account.logs.name}"
        existingStorageAccountResourceGroupName = "${azurerm_resource_group.logs.name}"
        table = "WADServiceFabric*EventTable"
    }
    deployment_mode = "Incremental"
    template_body = "${file("./arm_templates/logs.json")}"
}
