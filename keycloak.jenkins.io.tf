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

# This (sensitive) output is meant to be encrypted into the production secret system, to be provided as a secret to the keycloaks application https://admin.accounts.jenkins.io/auth/admin
output "keycloak_dbconfig" {
  sensitive   = true
  description = "YAML (secret) values for the Helm chart codecentric/keycloak"
  value       = <<-EOT
database:
  username: "${postgresql_role.keycloak.name}"
  password: "${random_password.pgsql_keycloak_user_password.result}"
  server: "${azurerm_postgresql_flexible_server.public.fqdn}"
  name: "${postgresql_database.keycloak.name}"
secrets:
    db:
        data:
            DB_USER: ${base64encode(postgresql_role.keycloak.name)}
            DB_PASSWORD: ${base64encode(random_password.pgsql_keycloak_user_password.result)}
            DB_VENDOR: cG9zdGdyZXM=
            DB_ADDR: ${base64encode(azurerm_postgresql_flexible_server.public.fqdn)}
            DB_PORT: NTQzMg==
            DB_DATABASE: ${base64encode(postgresql_database.keycloak.name)}
EOT
}
