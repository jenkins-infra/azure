resource "postgresql_database" "rating" {
  name  = "rating"
  owner = postgresql_role.rating.name
}

resource "random_password" "pgsql_rating_user_password" {
  length = 24
}

resource "postgresql_role" "rating" {
  name     = "rating"
  login    = true
  password = random_password.pgsql_rating_user_password.result
}

# This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the ratings.jenkins.io application
output "rating_dbconfig" {
  sensitive   = true
  description = "YAML helm (secret) values for the helm-chart jenkins-infra/rating"
  value       = <<-EOT
database:
  username: "${local.public_pgsql_admin_login}"
  password: "${random_password.pgsql_rating_user_password.result}"
  server: "${azurerm_postgresql_flexible_server.public.fqdn}"
  name: "${postgresql_database.rating.name}"
  EOT
}
