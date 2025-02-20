# TODO: delete once https://github.com/jenkins-infra/azure/pull/940 is applied with success
import {
  to       = kubernetes_namespace.ldap
  provider = kubernetes.publick8s
  id       = "ldap"
}
# TODO: delete once https://github.com/jenkins-infra/azure/pull/940 is applied with success
import {
  to = azurerm_storage_share.ldap
  id = "/subscriptions/dff2ec18-6a8e-405c-8e45-b7df7465acf0/resourceGroups/ldap/providers/Microsoft.Storage/storageAccounts/ldapjenkinsiobackups/fileServices/default/shares/ldap"
}
