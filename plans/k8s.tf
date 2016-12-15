resource "azurerm_resource_group" "k8s" {
  name     = "${var.prefix}k8s"
  location = "${var.location}"
  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_storage_account" "k8s" {
    name                = "${var.prefix}k8s"
    resource_group_name = "${azurerm_resource_group.releases.name}"
    location            = "${var.location}"
    account_type        = "Standard_GRS"
    depends_on          = ["azurerm_resource_group.k8s"]
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_template_deployment" "k8s"{
  name  = "${var.prefix}k8s"
  resource_group_name = "${ azurerm_resource_group.k8s.name }"
  depends_on          = ["azurerm_resource_group.k8s"]
  parameters = {
        sshRSAPublicKey = "${file("${var.ssh_pubkey_path}")}"
        dnsNamePrefix = "${var.prefix}"
# Bug with integer
#        agentCount = 1
#        masterCount = 1
        agentVMSize = "${var.k8s_agent_size}"
        linuxAdminUsername = "azureuser"
        orchestratorType = "Kubernetes"
        servicePrincipalClientId = "${var.client_id}"
        servicePrincipalClientSecret = "${var.client_secret}"
  }
  deployment_mode = "Incremental"
  template_body = "${file("./arm_templates/k8s")}"
}
