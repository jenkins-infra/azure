resource "postgresql_database" "keycloak" {
  name  = "keycloak"
  owner = postgresql_role.keycloak.name
}

resource "random_password" "pgsql_keycloak_user_password" {
  length           = 24
  override_special = "!#%&*()-_=+[]{}:?"
  special          = true
}

resource "postgresql_role" "keycloak" {
  name     = "keycloak"
  login    = true
  password = random_password.pgsql_keycloak_user_password.result
}

# This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the Keycloak application (https://admin.accounts.jenkins.io)
output "keycloak_dbconfig" {
  # default port to use: https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking
  # nothing to get from terraform for the port: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server#attributes-reference
  sensitive   = true
  description = "YAML (secret) values for the Helm chart codecentric/keycloak"
  value       = <<-EOT
secrets:
    db:
        data:
            DB_USER: ${base64encode(postgresql_role.keycloak.name)}
            DB_PASSWORD: ${base64encode(random_password.pgsql_keycloak_user_password.result)}
            DB_VENDOR: ${base64encode("postgres")}
            DB_ADDR: ${base64encode(azurerm_postgresql_flexible_server.public.fqdn)}
            DB_PORT: ${base64encode("5432")}
            DB_DATABASE: ${base64encode(postgresql_database.keycloak.name)}
EOT
}
