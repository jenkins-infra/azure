## Matomo Resources

# Database - ref. https://matomo.org/faq/how-to-install/faq_23484/
resource "mysql_database" "matomo" {
  name = "matomo"
}
resource "random_password" "matomo_mysql_password" {
  length           = 81
  lower            = true
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  numeric          = true
  override_special = "_"
  special          = true
  upper            = true
}
resource "mysql_user" "matomo" {
  user               = "matomo"
  host               = "*" # Default "localhost" forbids access from clusters
  plaintext_password = random_password.matomo_mysql_password.result
}
resource "mysql_grant" "matomo" {
  user       = mysql_user.matomo.user
  host       = mysql_user.matomo.host
  database   = mysql_database.matomo.name
  privileges = ["SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "INDEX", "DROP", "ALTER", "CREATE TEMPORARY TABLES", "LOCK TABLES"]
}

# This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the matomo application
output "matomo_dbconfig" {
  # Value of the port is fixed to 3306 (https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking and https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mysql_flexible_server#attributes-reference)
  sensitive   = true
  description = "YAML (secret) values for the Helm chart bitnami/matomo"
  value       = <<-EOT
externalDatabase:
  host: ${azurerm_mysql_flexible_server.public_db_mysql.fqdn}
  port: 3306
  database: ${mysql_database.matomo.name}
  user: ${mysql_user.matomo.user}
  password: ${random_password.matomo_mysql_password.result}
EOT
}
