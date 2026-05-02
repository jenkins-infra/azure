moved {
  from = azurerm_dns_a_record.cert_ci_jenkins_io_controller
  to   = module.cert_ci_jenkins_io.azurerm_dns_a_record.controller[0]
}
