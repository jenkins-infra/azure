####################################################################################
## Resources for the permanent agent VM
####################################################################################
removed {
  from = azurerm_network_interface.dummy_trusted_ci_jenkins_io

  lifecycle {
    destroy = false
  }
}
removed {
  from = azurerm_linux_virtual_machine.dummy_trusted_ci_jenkins_io

  lifecycle {
    destroy = false
  }
}
removed {
  from = azurerm_managed_disk.dummy_trusted_ci_jenkins_io_data

  lifecycle {
    destroy = false
  }
}
removed {
  from = azurerm_virtual_machine_data_disk_attachment.dummy_trusted_ci_jenkins_io_data

  lifecycle {
    destroy = false
  }
}
removed {
  from = azurerm_network_security_rule.allow_inbound_ssh_from_controller_to_dummy_agent

  lifecycle {
    destroy = false
  }
}
removed {
  from = azurerm_dns_a_record.trusted_dummy_agent

  lifecycle {
    destroy = false
  }
}
