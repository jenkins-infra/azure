resource "postgresql_database" "uplink" {
  name  = "uplink"
  owner = postgresql_role.uplink.name
}

resource "random_password" "pgsql_uplink_user_password" {
  length           = 24
  override_special = "!#%&*()-_=+[]{}:?"
  special          = true
}

resource "postgresql_role" "uplink" {
  name     = "uplinkadmin"
  login    = true
  password = random_password.pgsql_uplink_user_password.result
}

# This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the uplink.jenkins.io application
output "uplink_dbconfig" {
  sensitive   = true
  description = "YAML (secret) values for the Helm chart jenkins-infra/uplink"
  value       = <<-EOT
postgresql:
    url: postgres://${postgresql_role.uplink.name}:${random_password.pgsql_uplink_user_password.result}@${azurerm_postgresql_flexible_server.public_db.fqdn}:5432/${postgresql_database.uplink.name}
  EOT
}
