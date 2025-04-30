import {
  to = azurerm_dns_zone.cert_ci_jenkins_io
  id = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/proddns_jenkinsio/providers/Microsoft.Network/dnsZones/cert.ci.jenkins.io"
}

import {
  to = azurerm_dns_ns_record.cert_ci_jenkins_io
  id = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/proddns_jenkinsio/providers/Microsoft.Network/dnsZones/jenkins.io/NS/cert.ci"
}
