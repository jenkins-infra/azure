import {
  to = module.trusted_ci_jenkins_io_letsencrypt.azurerm_dns_zone.custom_zone
  id = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/proddns_jenkinsio/providers/Microsoft.Network/dnsZones/trusted.ci.jenkins.io"
}

import {
  to = module.trusted_ci_jenkins_io_letsencrypt.azurerm_dns_ns_record.custom_zone_parent_records
  id = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/proddns_jenkinsio/providers/Microsoft.Network/dnsZones/jenkins.io/NS/trusted.ci"
}
