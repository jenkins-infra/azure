resource "azurerm_resource_group" "dockerregistry" {
  name     = "${var.prefix}dockerregistry"
  location = "${var.location}"
  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "dockerregistry" {
    name                = "${var.prefix}dockerregistry"
    resource_group_name = "${azurerm_resource_group.dockerregistry.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_template_deployment" "dockerregistry"{
  name  = "${var.prefix}dockerregistry"
  resource_group_name = "${ azurerm_resource_group.dockerregistry.name }"
  parameters = {
	registryName = "${var.prefix}registry"
 	registryLocation = "${var.location}"
	registryApiVersion = "2016-06-27-preview"
	storageAccountName = "${ azurerm_storage_account.dockerregistry.name }"
	storageAccountType = "${ azurerm_storage_account.dockerregistry.account_type }"
	#adminUserEnabled = true	
  }
  deployment_mode = "Incremental"
  template_body = <<DEPLOY
{
    "$schema": "http://schema.management.azure.com/schemas/2014-04-01-preview/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "registryName": {
            "type": "String",
            "metadata": {
                "description": "Name of the registry service"
            }
        },
        "registryLocation": {
            "type": "String",
            "metadata": {
                "description": "Location of the registry service"
            }
        },
        "registryApiVersion": {
            "defaultValue": "2016-06-27-preview",
            "type": "String",
            "metadata": {
                "description": "Api version of the registry service"
            }
        },
        "storageAccountName": {
            "type": "String",
            "metadata": {
                "description": "Name of the storage account"
            }
        },
        "storageAccountType": {
            "defaultValue": "Standard_LRS",
            "type": "String",
            "metadata": {
                "description": "Type of the storage account"
            }
        },
        "adminUserEnabled": {
            "defaultValue": false,
            "type": "Bool",
            "metadata": {
                "description": "Enable admin user"
            }
        }
    },
    "resources": [
        {
            "type": "Microsoft.Storage/storageAccounts",
            "sku": {
                "name": "[parameters('storageAccountType')]"
            },
            "kind": "Storage",
            "name": "[parameters('storageAccountName')]",
            "apiVersion": "2016-01-01",
            "location": "[parameters('registryLocation')]",
            "tags": {
                "containerregistry": "[parameters('registryName')]"
            },
            "properties": {
                "encryption": {
                    "services": {
                        "blob": {
                            "enabled": true
                        }
                    },
                    "keySource": "Microsoft.Storage"
                }
            }
        },
        {
            "type": "Microsoft.ContainerRegistry/registries",
            "name": "[parameters('registryName')]",
            "apiVersion": "[parameters('registryApiVersion')]",
            "location": "[parameters('registryLocation')]",
            "properties": {
                "adminUserEnabled": "[parameters('adminUserEnabled')]",
                "storageAccount": {
                    "name": "[parameters('storageAccountName')]",
                    "accessKey": "[listKeys(resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName')), '2016-01-01').keys[0].value]"
                }
            },
            "dependsOn": [
                "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]"
            ]
        }
    ]
}
DEPLOY
}
