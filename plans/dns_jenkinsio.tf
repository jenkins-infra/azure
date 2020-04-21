#
# This terraform plan defines the resources necessary for DNS setup of jenkins.io
#

locals {
  jenkinsio_a_records = {
    # Root
    "@" = "52.147.174.4"
    # Physical machine at Contegix
    cucumber = "199.193.196.24"
    # VM at Rackspace
    celery = "162.242.234.101"
    okra   = "162.209.106.32"
    # cabbage has died of dysentery
    cabbage = "104.130.167.56"
    kelp    = "162.209.124.149"
    # Hosts at OSUOSL
    lettuce = "140.211.9.32"
    # artichoke has died of dysentery
    artichoke = "140.211.9.22"
    eggplant  = "140.211.15.101"
    edamame   = "140.211.9.2"
    radish    = "140.211.9.94"
    # EC2
    rating  = "52.23.130.110"
    mirrors = "52.202.51.185"
    l10n    = "52.71.7.244"
    census  = "52.202.38.86"
    usage   = "52.204.62.78"
    # Azure
    ldap          = "40.70.191.84"
    "azure.ci"    = "104.208.238.39"
    ci            = "104.208.238.39"
    "private.aks" = "10.0.2.5"
    "public.aks"  = "52.147.174.4"
  }

  jenkinsio_aaaa_records = {
    # VM at Rackspace
    celery = "2001:4802:7801:103:be76:4eff:fe20:357c"
    okra   = "2001:4802:7800:2:be76:4eff:fe20:7a31"
  }

  jenkinsio_cname_records = {
    # Azure
    accounts         = "public.aks.jenkins.io"
    "archives.azure" = "public.aks.jenkins.io"
    "mirror.azure"   = "public.aks.jenkins.io"
    get              = "public.aks.jenkins.io"
    javadoc          = "public.aks.jenkins.io"
    plugins          = "d.sni.global.fastly.net"
    reports          = "public.aks.jenkins.io"
    www              = "jenkins.io"
    uplink           = "public.aks.jenkins.io"

    # AKS
    "release.repo"      = "private.aks.jenkins.io"
    "release.ci"        = "private.aks.jenkins.io"
    "infra.ci"          = "private.aks.jenkins.io"
    "release.pkg"       = "private.aks.jenkins.io"
    "grafana.publick8s" = "private.aks.jenkins.io"
    "admin.polls"       = "private.aks.jenkins.io"
    "private.dex "      = "private.aks.jenkins.io"
    polls               = "public.aks.jenkins.io"

    # Fastly
    "_acme-challenge.plugins" = "tr8qxfomlsxfq1grha.fastly-validations.com"
    "_acme-challenge" = "ohh97689e0dknl1rqp.fastly-validations.com"

    # CNAME Records
    pkg      = "mirrors.jenkins.io"
    puppet   = "radish.jenkins.io"
    updates  = "mirrors.jenkins.io"
    archives = "okra.jenkins.io"
    stats    = "jenkins-infra.github.io"
    patron   = "jenkins-infra.github.io"
    wiki     = "lettuce.jenkins.io"
    issues   = "edamame.jenkins.io"
    # Magical CNAME for certificate validation
    "D07F852F584FA592123140354D366066.ldap" = "75E741181A7ACDBE2996804B2813E09B65970718.comodoca.com"
    # Amazon SES configuration to send out email from noreply@jenkins.io
    "pbssnl2yyudgfdl3flznotnarnamz5su._domainkey" = "pbssnl2yyudgfdl3flznotnarnamz5su.dkim.amazonses.com"
    "6ch6fw67efpfgoqyhdhs2cy2fpkwrvsk._domainkey" = "6ch6fw67efpfgoqyhdhs2cy2fpkwrvsk.dkim.amazonses.com"
    "37qo4cqmkxeocwr2iicjop77fq52m6yh._domainkey" = "37qo4cqmkxeocwr2iicjop77fq52m6yh.dkim.amazonses.com"
    # Others
    "_26F1803EE76B9FFE3884B762F77A11B5.ldap" = "BB7DE2B47B0E47A15260A401C6A5477E.F6289F84FFAA8F222EE876DEE5D91C0C.5ac644adc424f.comodoca.com"
  }

  jenkinsio_txt_records = {
    # Amazon SES configuration to send out email from noreply@jenkins.io
    _amazonses = "kYNeW+b+9GnKO/LzqP/t0TzLyN86jQ9didoBAJSjezE="
    # mailgun configuration
    "mailo._domainkey" = "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCpS+8K+bVvFlfTqbVbuvM9SoX0BqjW3zK7BJeCZ4GnaJTeRaurKx81hUX1wz3wKt+Qt9xI+X6mAlar2Co+B13GsNZIlYVdO/zBVtZG+R5KvMQUynNyie05oRyaTFWtNEiQVgGYgM4xkwlIWSA9EXmBMaKg7ze3kKNKUOnzKDIxMQIDAQAB"
  }
}

resource "azurerm_resource_group" "dns_jenkinsio" {
  name     = "${var.prefix}dns_jenkinsio"
  location = var.location

  tags = {
    env = var.prefix
  }
}

resource "azurerm_dns_zone" "jenkinsio" {
  name                = "jenkins.io"
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
}

resource "azurerm_dns_a_record" "jenkinsio_a_entries" {
  count               = length(local.jenkinsio_a_records)
  name                = element(keys(local.jenkinsio_a_records), count.index)
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600

  records = [local.jenkinsio_a_records[element(keys(local.jenkinsio_a_records), count.index)]]
}

resource "azurerm_dns_aaaa_record" "jenkinsio_aaaa_entries" {
  count               = length(local.jenkinsio_aaaa_records)
  name                = element(keys(local.jenkinsio_aaaa_records), count.index)
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600

  records = [local.jenkinsio_aaaa_records[element(keys(local.jenkinsio_aaaa_records), count.index)]]
}

resource "azurerm_dns_cname_record" "jenkinsio_cname_entries" {
  count               = length(local.jenkinsio_cname_records)
  name                = element(keys(local.jenkinsio_cname_records), count.index)
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600
  record              = local.jenkinsio_cname_records[element(keys(local.jenkinsio_cname_records), count.index)]
}

resource "azurerm_dns_txt_record" "jenkinsio_txt_entries" {
  count               = length(local.jenkinsio_txt_records)
  name                = element(keys(local.jenkinsio_txt_records), count.index)
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600

  record {
    value = local.jenkinsio_txt_records[element(keys(local.jenkinsio_txt_records), count.index)]
  }
}

resource "azurerm_dns_txt_record" "jenkinsio_txt_root_entries" {
  name                = "@"
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600

  record {
    value = "google-site-verification=4Z81CA6VzprPWEbGFtNbJwWoZBTGmTp3dk7N0hbt87U"
  }

  record {
    value = "v=spf1 include:mailgun.org ~all"
  }

  record {
    value = "_globalsign-domain-verification=b1pmSjP4FyG8hkZunkD3Aoz8tK0FWCje80-YwtLeDU" # Fastly
  }
}

resource "azurerm_dns_txt_record" "jenkinsio_txt_azure_entries" {
  name                = "azure"
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600

  record {
    value = "MS=ms77162642"
  }

}

resource "azurerm_dns_mx_record" "jenkinsio_mx_entries" {
  name                = "@"
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
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
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
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
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600
  records             = [azurerm_public_ip.vpn.ip_address]
}

# Create cert ci internal endpoints
resource "azurerm_dns_a_record" "certci" {
  name                = "cert.ci"
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600
  records             = [azurerm_network_interface.certci_private.private_ip_address]
}

resource "azurerm_dns_a_record" "ciprivate" {
  name                = "ci.private"
  zone_name           = azurerm_dns_zone.jenkinsio.name
  resource_group_name = azurerm_resource_group.dns_jenkinsio.name
  ttl                 = 3600
  records             = [azurerm_network_interface.ci_public.private_ip_address]
}
