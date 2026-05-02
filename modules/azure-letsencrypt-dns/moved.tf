moved {
  from = azurerm_role_assignment.custom_zone_read
  to   = azurerm_role_assignment.custom_zone_read[0]
}

moved {
  from = azurerm_role_assignment.custom_zone_manage_acme_assets_txt_record
  to   = azurerm_role_assignment.custom_zone_manage_acme_assets_txt_record[0]
}

moved {
  from = azurerm_role_assignment.custom_zone_manage_acme_txt_record
  to   = azurerm_role_assignment.custom_zone_manage_acme_txt_record[0]
}
