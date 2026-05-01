moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.deny_all_inbound_to_controller
  to   = module.cert_ci_jenkins_io.azurerm_network_security_rule.deny_all_inbound_to_controller[0]
}

moved {
  from = module.trusted_ci_jenkins_io.azurerm_network_security_rule.deny_all_inbound_to_controller
  to   = module.trusted_ci_jenkins_io.azurerm_network_security_rule.deny_all_inbound_to_controller[0]
}

moved {
  from = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_inbound_jenkins_to_controller
  to   = module.cert_ci_jenkins_io.azurerm_network_security_rule.allow_inbound_jenkins_to_controller[0]
}

moved {
  from = module.trusted_ci_jenkins_io.azurerm_network_security_rule.allow_inbound_jenkins_to_controller
  to   = module.trusted_ci_jenkins_io.azurerm_network_security_rule.allow_inbound_jenkins_to_controller[0]
}
