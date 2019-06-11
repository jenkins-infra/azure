resource "azurerm_resource_group" "release-core" {
  name     = "${var.prefix}releasecore"
  location = "${var.location}"
}

### Release Certificate stored on key vault

resource "azurerm_key_vault" "release-core" {
  name                            = "${var.prefix}releasecore"
  location                        = "${azurerm_resource_group.release-core.location}"
  resource_group_name             = "${azurerm_resource_group.release-core.name}"
  tenant_id                       = "${var.tenant_id}"
  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false

  sku {
    name = "standard"
  }

  network_acls {
    bypass  = "AzureServices"
    default_action = "Allow" # As long as trusted.ci doesn't run inside a trusted azure network, we need to allow access by default
    ip_rules = [
      "13.68.206.234/32",
      "40.70.215.138/32"
    ]
    virtual_network_subnet_ids = [
      "${azurerm_subnet.public_data.id}",
    ]
  }
}

# https://docs.microsoft.com/en-us/rest/api/keyvault/certificates-and-policies
resource "azurerm_key_vault_certificate" "release-core" {
  name         = "${var.prefix}releasecore"
  key_vault_id = "${azurerm_key_vault.release-core.id}"

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "digitalSignature",
        "cRLSign",
        "keyEncipherment",
        "dataEncipherment",
        "keyAgreement",
        "keyCertSign",
      ]

      subject            = "CN=jenkins.io"
      validity_in_months = 36
    }
  }
}

### GPG key stored on a storage account 

resource "azurerm_storage_account" "release-core" {
  name                     = "${var.prefix}releasecore"
  resource_group_name      = "${azurerm_resource_group.release-core.name}"
  location                 = "${var.location}"
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "release-core-gpg" {
  name                  = "gpg"
  resource_group_name   = "${azurerm_resource_group.release-core.name}"
  storage_account_name  = "${azurerm_storage_account.release-core.name}"
  container_access_type = "container"
}
