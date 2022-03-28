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
