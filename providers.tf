# Configure the Microsoft Azure Provider
provider "azurerm" {
  subscription_id                 = "dff2ec18-6a8e-405c-8e45-b7df7465acf0"
  resource_provider_registrations = "none"
  features {}
}
provider "azurerm" {
  alias                           = "jenkins-sponsorship"
  subscription_id                 = "1311c09f-aee0-4d6c-99a4-392c2b543204"
  resource_provider_registrations = "none"
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
  host                   = local.aks_clusters_outputs.cijenkinsio_agents_1.cluster_hostname
  client_certificate     = base64decode(azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.cijenkinsio_agents_1.kube_config.0.cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "infracijenkinsio_agents_1"
  host                   = local.aks_clusters_outputs.infracijenkinsio_agents_1.cluster_hostname
  client_certificate     = base64decode(azurerm_kubernetes_cluster.infracijenkinsio_agents_1.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.infracijenkinsio_agents_1.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.infracijenkinsio_agents_1.kube_config.0.cluster_ca_certificate)
}

provider "postgresql" {
  /**
  Reaching this DB requires:
  - VPN access (with proper routing)
  - The following line added in your `/etc/hosts` as there are no public DNS: `10.253.0.4      public-db.postgres.database.azure.com`
  **/
  host      = azurerm_postgresql_flexible_server.public_db.fqdn
  username  = local.public_db_pgsql_admin_login
  password  = random_password.public_db_pgsql_admin_password.result
  superuser = false
}

provider "mysql" {
  /**
  Reaching this DB requires:
  - VPN access (with proper routing)
  - The following line added in your `/etc/hosts` as there are no public DNS: `10.253.1.4     public-db-mysql.mysql.database.azure.com`
  **/
  endpoint = "${azurerm_mysql_flexible_server.public_db_mysql.fqdn}:3306"
  username = local.public_db_mysql_admin_login
  password = random_password.public_db_mysql_admin_password.result
  tls      = true # Mandatory for Azure MySQL Flexible instances
}
