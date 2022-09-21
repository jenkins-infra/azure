resource "postgresql_database" "plugin_health" {
  name  = "plugin_health"
  owner = postgresql_role.plugin_health.name
}

resource "random_password" "pgsql_plugin_health_user_password" {
  length           = 24
  override_special = "!#%&*()-_=+[]{}:?"
  special          = true
}

resource "postgresql_role" "plugin_health" {
  name     = "plugin_health"
  login    = true
  password = random_password.pgsql_plugin_health_user_password.result
}

# This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the plugin-health.jenkins.io application
output "plugin_health_dbconfig" {
  sensitive   = true
  description = "YAML (secret) values for the Helm chart jenkins-infra/plugin-health-scoring"
  value       = <<-EOT
database:
  username: "${postgresql_role.plugin_health.name}"
  password: "${random_password.pgsql_plugin_health_user_password.result}"
  server: "${azurerm_postgresql_flexible_server.public.fqdn}"
  name: "${postgresql_database.plugin_health.name}"
  EOT
}
