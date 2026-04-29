locals {
  service_custom_name         = var.service_custom_name != "" ? var.service_custom_name : var.service_fqdn
  service_short_name          = trimprefix(trimprefix(var.service_fqdn, var.dns_zone), ".")
  service_short_stripped_name = replace(local.service_short_name, ".", "-")
  service_stripped_name       = replace(var.service_fqdn, ".", "-")
  controller_fqdn             = "controller.${var.service_fqdn}"
  controller_principal_id     = var.controller_service_principal_end_date == "" ? data.azurerm_virtual_machine.controller.identity[0].principal_id : azuread_service_principal.controller[0].object_id
}
