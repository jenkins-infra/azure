resource "postgresql_database" "rating" {
  name  = "rating"
  owner = postgresql_role.rating.name
}

resource "random_password" "pgsql_rating_user_password" {
  length           = 24
  override_special = "!#%&*()-_=+[]{}:?"
  special          = true
}

resource "postgresql_role" "rating" {
  name     = "rating"
  login    = true
  password = random_password.pgsql_rating_user_password.result
}

# This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the ratings.jenkins.io application
output "rating_dbconfig" {
  sensitive   = true
  description = "YAML (secret) values for the Helm chart jenkins-infra/rating"
  value       = <<-EOT
database:
  username: "${postgresql_role.rating.name}"
  password: "${random_password.pgsql_rating_user_password.result}"
  server: "${azurerm_postgresql_flexible_server.public.fqdn}"
  name: "${postgresql_database.rating.name}"
  EOT
}
