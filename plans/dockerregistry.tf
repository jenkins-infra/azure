resource "azurerm_resource_group" "dockerregistry" {
  name     = "${var.prefix}dockerregistry"
  location = "${var.location}"
  tags {
    "env" = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "dockerregistry" {
    name                = "${var.prefix}dockerregistry"
    resource_group_name = "${azurerm_resource_group.dockerregistry.name}"
    location            = "${var.location}"
    depends_on          = ["azurerm_resource_group.dockerregistry"]
    account_type        = "Standard_GRS"
    tags {
        "env" = "${var.prefix}"
    }
}

resource "azurerm_template_deployment" "dockerregistry"{
  name  = "${var.prefix}dockerregistry"
  resource_group_name = "${ azurerm_resource_group.dockerregistry.name }"
  depends_on          = ["azurerm_resource_group.dockerregistry"]
  parameters = {
	registryName = "${var.prefix}registry"
 	registryLocation = "${var.location}"
	registryApiVersion = "2016-06-27-preview"
	storageAccountName = "${ azurerm_storage_account.dockerregistry.name }"
	#adminUserEnabled = true	
  }
  deployment_mode = "Incremental"
  template_body = "${file("./arm_templates/dockerregistry.json")}"
}
