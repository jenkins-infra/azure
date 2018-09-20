#
# This terraform plan defines the resources necessary for DNS setup of jenkins.io
#

locals {
  a_records = {
    # Root
    "@" = "40.79.70.97"

    # Physical machine at Contegix
    cucumber = "199.193.196.24"

    # VM at Rackspace
    celery = "162.242.234.101"
    okra = "162.209.106.32"

    # cabbage has died of dysentery
    cabbage = "104.130.167.56"
    kelp = "162.209.124.149"

    # Hosts at OSUOSL
    lettuce = "140.211.9.32"

    # artichoke has died of dysentery
    artichoke = "140.211.9.22"
    eggplant = "140.211.15.101"
    edamame = "140.211.9.2"

    # Others
    lists = "140.211.166.34"
    ns1 = "140.211.9.2"
    ns2 = "162.209.124.149"
    ns3 = "162.209.106.32"
  }

  aaaa_records = {
  }
  
  cname_records = {
  }

  txt_records = {
  }
}

resource "azurerm_resource_group" "jenkinsci_dns" {
  name     = "${var.prefix}jenkinsci_dns"
  location = "${var.location}"
  tags {
      env = "${var.prefix}"
  }
}

resource "azurerm_dns_zone" "jenkinsci" {
  name                = "jenkins-ci.org"
  resource_group_name = "${azurerm_resource_group.jenkinsci_dns.name}"
}

resource "azurerm_dns_a_record" "a_entries" {
  count               = "${length(local.a_records)}"
  name                = "${element(keys(local.a_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.jenkinsci_dns.name}"
  ttl                 = 3600
  records             = ["${local.a_records[element(keys(local.a_records), count.index)]}"]
}

resource "azurerm_dns_aaaa_record" "aaaa_entries" {
  count               = "${length(local.aaaa_records)}"
  name                = "${element(keys(local.aaaa_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.jenkinsci_dns.name}"
  ttl                 = 3600
  records             = ["${local.aaaa_records[element(keys(local.aaaa_records), count.index)]}"]
}

resource "azurerm_dns_cname_record" "cname_entries" {
  count               = "${length(local.cname_records)}"
  name                = "${element(keys(local.cname_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.jenkinsci_dns.name}"
  ttl                 = 3600
  record             = "${local.cname_records[element(keys(local.cname_records), count.index)]}"
}

resource "azurerm_dns_txt_record" "txt_entries" {
  count               = "${length(local.txt_records)}"
  name                = "${element(keys(local.txt_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.jenkinsci_dns.name}"
  ttl                 = 3600
  record {
    value = "${local.txt_records[element(keys(local.txt_records), count.index)]}"
  }
}

resource "azurerm_dns_mx_record" "mx_entries" {
  name                = "spamtrap"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.jenkinsci_dns.name}"
  ttl                 = 3600

  record {
    preference = 10
    exchange   = "mxa.mailgun.org."
  }

  record {
    preference = 10
    exchange   = "mxb.mailgun.org."
  }
}
