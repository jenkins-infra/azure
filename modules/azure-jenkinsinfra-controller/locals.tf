locals {
  service_short_name          = trimprefix(trimprefix(var.service_fqdn, "jenkins.io"), ".")
  service_short_stripped_name = replace(local.service_short_name, ".", "-")
  service_stripped_name       = replace(var.service_fqdn, ".", "-")
  controller_fqdn             = var.controller_fqdn == "" ? "controller.${var.service_fqdn}" : var.controller_fqdn
  controller_principal_id     = var.controller_service_principal_end_date == "" ? data.azurerm_virtual_machine.controller.identity[0].principal_id : azuread_service_principal.controller[0].object_id
  nsg_name                    = var.use_vnet_common_nsg ? data.azurerm_network_security_group.vnet_common_nsg[0].name : azurerm_network_security_group.controller[0].name
  nsg_rg_name                 = var.use_vnet_common_nsg ? data.azurerm_network_security_group.vnet_common_nsg[0].resource_group_name : azurerm_network_security_group.controller[0].resource_group_name
  nsg_rule_name_discriminator = var.use_vnet_common_nsg ? replace(local.controller_fqdn, ".jenkins.io", ".jio") : "${local.service_short_stripped_name}-controller"
  controller_inbound_ipv4_list = compact(flatten([
    [for ip in azurerm_linux_virtual_machine.controller.private_ip_addresses :
      ip if can(cidrnetmask("${ip}/32"))
    ],
    var.is_public ? azurerm_public_ip.controller[0].ip_address : "",
  ]))
}
