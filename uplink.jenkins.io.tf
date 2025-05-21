
removed {
  from = postgresql_database.uplink

  lifecycle {
    destroy = false
  }
}
# resource "postgresql_database" "uplink" {
#   name  = "uplink"
#   owner = postgresql_role.uplink.name
# }

removed {
  from = random_password.pgsql_uplink_user_password

  lifecycle {
    destroy = false
  }
}
# resource "random_password" "pgsql_uplink_user_password" {
#   length           = 24
#   override_special = "!#%&*()-_=+[]{}:?"
#   special          = true
# }

removed {
  from = postgresql_role.uplink

  lifecycle {
    destroy = false
  }
}
# resource "postgresql_role" "uplink" {
#   name     = "uplinkadmin"
#   login    = true
#   password = random_password.pgsql_uplink_user_password.result
# }

# # This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the uplink.jenkins.io application
# output "uplink_dbconfig" {
#   sensitive   = true
#   description = "YAML (secret) values for the Helm chart jenkins-infra/uplink"
#   value       = <<-EOT
# postgresql:
#     url: postgres://${postgresql_role.uplink.name}:${random_password.pgsql_uplink_user_password.result}@${azurerm_postgresql_flexible_server.public_db.fqdn}:5432/${postgresql_database.uplink.name}
#   EOT
# }

## TODO: remove once the DB is migrated in public-db
resource "azurerm_postgresql_flexible_server" "uplink_migration_runtime" {
  name                          = "uplink-migration-runtime"
  resource_group_name           = data.azurerm_resource_group.public.name
  location                      = var.location
  public_network_access_enabled = true
  administrator_login           = "pgadmin"
  # administrator_password is defined in SOPS (in config/uplink/migration-runtime-server-secrets.yaml)
  sku_name     = "GP_Standard_D4ds_v4"
  storage_mb   = "131072"
  storage_tier = "P10"
  version      = "13"
  zone         = "1"
}
