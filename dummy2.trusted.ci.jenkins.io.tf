####################################################################################
## Resources for the permanent agent VM
####################################################################################
resource "azurerm_network_interface" "dummy2_trusted_ci_jenkins_io" {
  provider            = azurerm.jenkins-sponsored
  name                = "dummy2-trusted-ci-jenkins-io"
  location            = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.location
  resource_group_name = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.trusted_ci_jenkins_io_sponsored_permanent_agents.id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_linux_virtual_machine" "dummy2_trusted_ci_jenkins_io" {
  provider                        = azurerm.jenkins-sponsored
  name                            = "dummy2.trusted.ci.jenkins.io"
  resource_group_name             = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.name
  location                        = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.location
  tags                            = local.default_tags
  size                            = "Standard_B2s"
  admin_username                  = local.admin_username
  zone                            = "1" # We need a zonale deployment to attach a Premium_SSD_v2 data disk
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.dummy2_trusted_ci_jenkins_io.id,
  ]

  admin_ssh_key {
    username   = local.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCtE5B08WVIJ1ir/oGiXea3y5wQOftepJLxyc0ePMCFFaOLLHrvZi36W+nWbJcSmN5tVU9A1CD1y9V7W0pJTowgGiWq6IfFlqkz/41k/MnSsJdGuJNWvDxGy3ECt2ej+MoUsdOTeF3aOX+yXHMBO6l4RYYtx28K/+w01sDNxJinvZakSSsgDNzdokh4Yq5ewGNQX5RXcfkOg+4BM4vkLTeXtupY7woZjhCnQGzuWY3IRICeFcYcl6bSTlEy2WFBc6MuKIFXxkC8oTLXm6+snZq+HbmZOApr7tG1LLXtWeiuUVp+IAQgI9con34ee/NlXPw+ZLr/kJ0+LxROdhNoWlCyLNjd2i/4o0SrRNXIB2Y4L8mMMsN5+MIIES+moIyTdD8lCvYlvE5qsnq01sKQLMHz8LUsKKc2zj8J3PPu2GbtGfvYJa8CU4W2xyxfKy0IUHzyLG6Gn87nlp+Cs5wLrH7cnqEkJ47Wzwinu7x86Bj7tkZMHwZnEh/1dzhGSwRJKxKu9MPEMgnVK/Tj58aXM6ptBs6UJNLWN04YAW3iDiLpLvwQqDCCrHP7cBUdvHndjQ8T1aCmqy5F1gATZUozVzKUWko33dkXBJpfsGtFYB+IuXDPtfSEPY7dp90Kzq3gqRe+Vf+c/Zlsv64AP1CR9DNcDUjXWQ+BKDW0CGX2xe6UkQ== jenkins-infra-team@googlegroups.com"
  }

  user_data = base64encode(
    templatefile("./.shared-tools/terraform/cloudinit.tftpl", {
      hostname       = "dummy.trusted.ci.jenkins.io",
      admin_username = local.admin_username,
      }
  ))
  computer_name = "dummy.trusted.ci.jenkins.io"

  # Encrypt all disks (ephemeral, temp dirs and data volumes) - https://learn.microsoft.com/en-us/azure/virtual-machines/disks-enable-host-based-encryption-portal?tabs=azure-powershell
  encryption_at_host_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = "32" # Minimum size with Ubuntu base image
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-minimal-jammy"
    sku       = "minimal-22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins.id,
      azurerm_user_assigned_identity.trusted_ci_jenkins_io_azurevm_agents_jenkins_sponsored.id,
    ]
  }
}

# data disk from dummy, moved in the new RG
import {
  to = azurerm_managed_disk.dummy_trusted_ci_jenkins_io_data_moved
  id = "/subscriptions/1e7d5219-acbc-4495-8629-bdbb22e9b3ed/resourceGroups/trusted-ci-jenkins-io-sponsored-permanent-agents/providers/Microsoft.Compute/disks/dummy-trusted-ci-jenkins-io-data"
}
resource "azurerm_managed_disk" "dummy_trusted_ci_jenkins_io_data_moved" {
  name                 = "dummy-trusted-ci-jenkins-io-data"
  location             = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.location
  resource_group_name  = azurerm_resource_group.trusted_ci_jenkins_io_permanent_agents_jenkins_sponsored.name
  zone                 = 2 # forcing the new data disk zone instead of azurerm_linux_virtual_machine.dummy2_trusted_ci_jenkins_io.zone
  storage_account_type = "PremiumV2_LRS"
  create_option        = "Empty"
  disk_size_gb         = "580"
  tags                 = local.default_tags
}

## Commented out as it fails due to zone mismatch between VM and disk
#resource "azurerm_virtual_machine_data_disk_attachment" "dummy2_trusted_ci_jenkins_io_data" {
#  provider           = azurerm.jenkins-sponsored
#  managed_disk_id    = azurerm_managed_disk.dummy_trusted_ci_jenkins_io_data_moved.id
#  virtual_machine_id = azurerm_linux_virtual_machine.dummy2_trusted_ci_jenkins_io.id
#  lun                = "20"
#  caching            = "None" # Caching not supported with "PremiumV2_LRS"
#}

# No NSG

####################################################################################
## Public DNS records
####################################################################################
resource "azurerm_dns_a_record" "trusted_dummy2_agent" {
  name                = "dummy2"
  zone_name           = module.trusted_ci_jenkins_io_letsencrypt.zone_name
  resource_group_name = data.azurerm_resource_group.proddns_jenkinsio.name
  ttl                 = 60
  records             = [azurerm_linux_virtual_machine.dummy2_trusted_ci_jenkins_io.private_ip_address]
}
