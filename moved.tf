moved {
  from = azurerm_dns_zone.cert_ci_jenkins_io
  to   = module.cert_ci_jenkins_io_letsencrypt.azurerm_dns_zone.custom_zone
}

moved {
  from = azurerm_dns_ns_record.cert_ci_jenkins_io
  to   = module.cert_ci_jenkins_io_letsencrypt.azurerm_dns_ns_record.custom_zone_parent_records
}

moved {
  from = azurerm_role_assignment.cert_ci_jenkins_io_dns
  to   = module.cert_ci_jenkins_io_letsencrypt.azurerm_role_assignment.custom_zone_read
}
