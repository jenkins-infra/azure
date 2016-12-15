variable "subscription_id" {}
variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}
variable "prefix" {}
variable "location" {
    type    = "string"
    default = "East US"
}

# Port used for Puppet agents to connect to a Puppet master
variable "puppet_master_port" {
    default = 8140
}
