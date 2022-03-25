locals {
  public_pgsql_admin_login = "psqladmin${random_password.pgsql_admin_login.result}"
}