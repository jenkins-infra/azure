#
# This terraform plan defines the resources necessary for DNS setup of jenkins.io
#

locals {
  a_records = {
    cucumber = "199.193.196.24"
    celery = "162.242.234.101"
    okra = "162.209.106.32"
    cabbage = "104.130.167.56"
    kelp = "162.209.124.149"
  }
  aaaa_records = {}
  cname_records = {}
}

resource "azurerm_resource_group" "jenkinsio_dns" {
  name     = "${var.prefix}jenkinsio_dns"
  location = "${var.location}"
  tags {
      env = "${var.prefix}"
  }
}

resource "azurerm_dns_zone" "jenkinsio" {
  name                = "jenkins.io"
  resource_group_name = "${azurerm_resource_group.jenkinsio_dns.name}"
}

resource "azurerm_dns_a_record" "a_entries" {
  count               = "${length(local.a_records)}"
  name                = "${element(keys(local.a_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.jenkinsio_dns.name}"
  ttl                 = 3600
  records             = ["${local.a_records[element(keys(local.a_records), count.index)]}"]
}
