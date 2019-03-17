#
# This terraform plan defines the resources necessary for DNS setup of jenkins.io
#

locals {
  jenkinsio_a_records = {
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
    radish = "140.211.9.94"

    # EC2
    rating = "52.23.130.110"
    mirrors = "52.202.51.185"
    ci = "52.71.231.250"
    l10n = "52.71.7.244"
    census = "52.202.38.86"
    usage = "52.204.62.78"

    # Azure
    ldap = "52.232.180.203"
    cn = "159.138.4.250" # Chinese jenkins.io hosted Huawei China
    azure.ci = "104.208.238.39"
    gateway.evergreen = "137.116.80.151"
  }

  jenkinsio_aaaa_records = {
    # VM at Rackspace
    celery = "2001:4802:7801:103:be76:4eff:fe20:357c"
    okra = "2001:4802:7800:2:be76:4eff:fe20:7a31"
  }
  
  jenkinsio_cname_records = {
    # Azure
    accounts = "nginx.azure.jenkins.io"
    nginx.azure = "jenkins.io"
    javadoc = "nginx.azure.jenkins.io"
    plugins = "nginx.azure.jenkins.io"
    repo.azure = "nginx.azure.jenkins.io"
    updates.azure = "nginx.azure.jenkins.io"
    reports = "nginx.azure.jenkins.io"
    www = "nginx.azure.jenkins.io"
    evergreen = "nginx.azure.jenkins.io"
    uplink = "nginx.azure.jenkins.io"

    # CNAME Records
    pkg = "mirrors.jenkins.io"
    puppet = "radish.jenkins.io"
    updates = "mirrors.jenkins.io"
    archives = "okra.jenkins.io"
    stats = "jenkins-infra.github.io"
    patron = "jenkins-infra.github.io"
    wiki = "lettuce.jenkins.io"
    issues = "edamame.jenkins.io"

    # Magical CNAME for certificate validation
    "D07F852F584FA592123140354D366066.ldap" = "75E741181A7ACDBE2996804B2813E09B65970718.comodoca.com"

    # Amazon SES configuration to send out email from noreply@jenkins.io
    pbssnl2yyudgfdl3flznotnarnamz5su._domainkey = "pbssnl2yyudgfdl3flznotnarnamz5su.dkim.amazonses.com"
    "6ch6fw67efpfgoqyhdhs2cy2fpkwrvsk._domainkey" = "6ch6fw67efpfgoqyhdhs2cy2fpkwrvsk.dkim.amazonses.com"
    "37qo4cqmkxeocwr2iicjop77fq52m6yh._domainkey" = "37qo4cqmkxeocwr2iicjop77fq52m6yh.dkim.amazonses.com"

    # Others
    "_26F1803EE76B9FFE3884B762F77A11B5.ldap" = "BB7DE2B47B0E47A15260A401C6A5477E.F6289F84FFAA8F222EE876DEE5D91C0C.5ac644adc424f.comodoca.com"
  }

  jenkinsio_txt_records = {
    # Amazon SES configuration to send out email from noreply@jenkins.io    
    _amazonses = "kYNeW+b+9GnKO/LzqP/t0TzLyN86jQ9didoBAJSjezE="
    # mailgun configuration
    "@" = "v=spf1 include:mailgun.org ~all"
    mailo._domainkey = "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCpS+8K+bVvFlfTqbVbuvM9SoX0BqjW3zK7BJeCZ4GnaJTeRaurKx81hUX1wz3wKt+Qt9xI+X6mAlar2Co+B13GsNZIlYVdO/zBVtZG+R5KvMQUynNyie05oRyaTFWtNEiQVgGYgM4xkwlIWSA9EXmBMaKg7ze3kKNKUOnzKDIxMQIDAQAB"
  }
}

resource "azurerm_resource_group" "dns_jenkinsio" {
  name     = "${var.prefix}dns_jenkinsio"
  location = "${var.location}"
  tags {
      env = "${var.prefix}"
  }
}

resource "azurerm_dns_zone" "jenkinsio" {
  name                = "jenkins.io"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
}

resource "azurerm_dns_a_record" "jenkinsio_a_entries" {
  count               = "${length(local.jenkinsio_a_records)}"
  name                = "${element(keys(local.jenkinsio_a_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600
  records             = ["${local.jenkinsio_a_records[element(keys(local.jenkinsio_a_records), count.index)]}"]
}

resource "azurerm_dns_aaaa_record" "jenkinsio_aaaa_entries" {
  count               = "${length(local.jenkinsio_aaaa_records)}"
  name                = "${element(keys(local.jenkinsio_aaaa_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600
  records             = ["${local.jenkinsio_aaaa_records[element(keys(local.jenkinsio_aaaa_records), count.index)]}"]
}

resource "azurerm_dns_cname_record" "jenkinsio_cname_entries" {
  count               = "${length(local.jenkinsio_cname_records)}"
  name                = "${element(keys(local.jenkinsio_cname_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600
  record             = "${local.jenkinsio_cname_records[element(keys(local.jenkinsio_cname_records), count.index)]}"
}

resource "azurerm_dns_txt_record" "jenkinsio_txt_entries" {
  count               = "${length(local.jenkinsio_txt_records)}"
  name                = "${element(keys(local.jenkinsio_txt_records), count.index)}"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600
  record {
    value = "${local.jenkinsio_txt_records[element(keys(local.jenkinsio_txt_records), count.index)]}"
  }
}

resource "azurerm_dns_mx_record" "jenkinsio_mx_entries" {
  name                = "@"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600

  record {
    preference = 10
    exchange   = "mxa.mailgun.org"
  }

  record {
    preference = 10
    exchange   = "mxb.mailgun.org"
  }
}

resource "azurerm_dns_mx_record" "spamtrap_jenkinsio_mx_entries" {
  name                = "spamtrap"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600

  record {
    preference = 10
    exchange   = "mxa.mailgun.org"
  }

  record {
    preference = 10
    exchange   = "mxb.mailgun.org"
  }
}

resource "azurerm_dns_a_record" "vpn" {
  name                = "vpn"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600
  records             = ["${azurerm_public_ip.vpn.ip_address}"]
}

# Create cert ci internal endpoints
resource "azurerm_dns_a_record" "certci" {
  name                = "cert.ci"
  zone_name           = "${azurerm_dns_zone.jenkinsio.name}"
  resource_group_name = "${azurerm_resource_group.dns_jenkinsio.name}"
  ttl                 = 3600
  records             = ["${azurerm_network_interface.certci_private.private_ip_address}"]
}
