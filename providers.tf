# Configure the Microsoft Azure Provider
provider "azurerm" {
  subscription_id            = local.subscription_main
  skip_provider_registration = "true"
  features {}
}
provider "azurerm" {
  alias                      = "jenkins-sponsorship"
  subscription_id            = local.subscription_sponsored
  skip_provider_registration = "true"
  features {}
}

provider "kubernetes" {
  alias                  = "privatek8s"
  host                   = azurerm_kubernetes_cluster.privatek8s.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.privatek8s.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.privatek8s.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.privatek8s.kube_config.0.cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "publick8s"
  host                   = data.azurerm_kubernetes_cluster.publick8s.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.publick8s.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.publick8s.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.publick8s.kube_config.0.cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "cijenkinsio_agents_1"
  host                   = azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.cluster_ca_certificate)
}

provider "postgresql" {
  /**
  Important: terraform must be allowed to reach this instance through the network. Check the followings:
  - If running in Jenkins, ensure that the subnet of the agents is peered to the subnet of this postgreSQL instance
    * Don't forget to also check the network security group rules
  - If running locally, ensure that:
    * your /etc/hosts defines an entry with <azurerm_postgresql_flexible_server.public.fqdn> to 127.0.0.1
    * you've opened an SSH tunnel such as `ssh -L 5432:<azurerm_postgresql_flexible_server.public.fqdn>:5432` through a machine of the private network
  **/
  host      = azurerm_postgresql_flexible_server.public_db.fqdn
  username  = local.public_db_pgsql_admin_login
  password  = random_password.public_db_pgsql_admin_password.result
  superuser = false
}

provider "mysql" {
  /**
  Important: terraform must be allowed to reach this instance through the network. Check the followings:
  - If running in Jenkins, ensure that the subnet of the agents is peered to the subnet of this mysql instance
    * Don't forget to also check the network security group rules
  - If running locally, ensure that:
    * your /etc/hosts defines an entry with <azurerm_mysql_flexible_server.public.fqdn> to 127.0.0.1
    * you've opened an SSH tunnel such as `ssh -L 3306:<azurerm_mysql_flexible_server.public.fqdn>:3306` through a machine of the private network
  **/
  endpoint = "${azurerm_mysql_flexible_server.public_db_mysql.fqdn}:3306"
  username = local.public_db_mysql_admin_login
  password = random_password.public_db_mysql_admin_password.result
  tls      = true # Mandatory for Azure MySQL Flexible instances
}
