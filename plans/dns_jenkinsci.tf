#
# This terraform plan defines the resources necessary for DNS setup of jenkins-ci.org
#

locals {
  jenkinsci_a_records = {
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

  jenkinsci_aaaa_records = {
    celery = "2001:4802:7801:103:be76:4eff:fe20:357c"
    okra = "2001:4802:7800:2:be76:4eff:fe20:7a31"
    kelp = "2001:4802:7801:101:be76:4eff:fe20:b252"
    ns2 = "2001:4802:7801:101:be76:4eff:fe20:b252"
  }
  
  jenkinsci_cname_records = {
    www = "jenkins-ci.org"
    issues = "edamame.jenkins-ci.org"
    wiki = "lettuce.jenkins-ci.org"
    updates = "updates.jenkins.io"
    javadoc = "javadoc.jenkins.io"
    gherkin = "cucumber.jenkins-ci.org"
    drupal = "cucumber.jenkins-ci.org"
    downloads = "cucumber.jenkins-ci.org"
    fisheye = "cucumber.jenkins-ci.org"
    stacktrace = "cucumber.jenkins-ci.org"
    sorcerer = "cucumber.jenkins-ci.org"
    maven = "cucumber.jenkins-ci.org"
    maven2 = "cucumber.jenkins-ci.org"
    ci = "ci.jenkins.io"
    svn = "cucumber.jenkins-ci.org"
    javanet2 = "cucumber.jenkins-ci.org"
    l10n = "l10n.jenkins.io"
    mirrors = "mirrors.jenkins.io"
    pkg = "pkg.jenkins.io"
    usage = "usage.jenkins.io"
    stats = "jenkins-infra.github.io"
    meetings = "edamame.jenkins-ci.org"
    jekyll = "jenkinsci.github.io"
    mirrors2 = "lettuce.jenkins-ci.org"
    ips = "lettuce.jenkins-ci.org"
    nagios = "lettuce.jenkins-ci.org"
    kale = "ec2-184-73-58-254.compute-1.amazonaws.com"
    repo = "jenkinsci.jfrog.org"
    links = "rhs.reddit.com"
    plugin-generator = "jpi-create.jenkins.cloudbees.net"
    goto = "goto.jenkins.cloudbees.net"
    recipe = "recipe.jenkins.cloudbees.net"
    puppet = "artichoke.jenkins-ci.org"
    archives = "okra.jenkins-ci.org"
    demo = "kelp.jenkins-ci.org"
    accounts = "accounts.jenkins.io"
  }
}

resource "azurerm_resource_group" "dns_jenkinsci" {
  name     = "${var.prefix}dns_jenkinsci"
  location = "${var.location}"
  tags {
      env = "${var.prefix}"
  }
}

resource "azurerm_dns_zone" "jenkinsci" {
  name                = "jenkins-ci.org"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsci.name}"
}

resource "azurerm_dns_a_record" "jenkinsci_a_entries" {
  count               = "${length(local.jenkinsci_a_records)}"
  name                = "${element(keys(local.jenkinsci_a_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsci.name}"
  ttl                 = 3600
  records             = ["${local.jenkinsci_a_records[element(keys(local.jenkinsci_a_records), count.index)]}"]
}

resource "azurerm_dns_aaaa_record" "jenkinsci_aaaa_entries" {
  count               = "${length(local.jenkinsci_aaaa_records)}"
  name                = "${element(keys(local.jenkinsci_aaaa_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsci.name}"
  ttl                 = 3600
  records             = ["${local.jenkinsci_aaaa_records[element(keys(local.jenkinsci_aaaa_records), count.index)]}"]
}

resource "azurerm_dns_cname_record" "jenkinsci_cname_entries" {
  count               = "${length(local.jenkinsci_cname_records)}"
  name                = "${element(keys(local.jenkinsci_cname_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsci.name}"
  ttl                 = 3600
  record             = "${local.jenkinsci_cname_records[element(keys(local.jenkinsci_cname_records), count.index)]}"
}

resource "azurerm_dns_txt_record" "jenkinsci_root_txt_entries" {
  name                = "@"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsci.name}"
  ttl                 = 3600
  record {
    value = "v=spf1 mx ip4:199.193.196.24 ip4:140.211.15.0/24 ip4:140.211.8.0/23 ip4:173.203.60.151 ip4:140.211.166.128/25 -all"
  }
}

resource "azurerm_dns_mx_record" "jenkinsci_root_mx_entries" {
  name                = "@"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsci.name}"
  ttl                 = 3600

  record {
    preference = 0
    exchange   = "cucumber.jenkins-ci.org"
  }
}

resource "azurerm_dns_mx_record" "jenkinsci_mx_entries" {
  name                = "lists"
  zone_name           = "${azurerm_dns_zone.jenkinsci.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsci.name}"
  ttl                 = 3600

  record {
    preference = 0
    exchange   = "smtp1.osuosl.org"
  }

  record {
    preference = 0
    exchange   = "smtp2.osuosl.org"
  }

  record {
    preference = 0
    exchange   = "smtp3.osuosl.org"
  }

  record {
    preference = 0
    exchange   = "smtp4.osuosl.org"
  }
}
