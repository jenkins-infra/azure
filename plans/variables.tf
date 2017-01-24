variable "subscription_id" {}
variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}
variable "prefix" {}
variable "dockerregistrylocation" {
    type    = "string"
    default = "East US"
}
variable "location" {
    type    = "string"
    default = "East US 2"
}
# Port used for Puppet agents to connect to a Puppet master
variable "puppet_master_port" {
    default = 8140
}
# Define kubernetes agent instance size
variable "k8s_agent_size" {
    type = "string"
    default = "Standard_D2_v2"
}
# Define default ssh public key path used to provision new kubernetes agent
variable "ssh_pubkey_path"{
    type = "string"
    default = "./ssh_key/dummyk8s_rsa.pub"
}

variable "logslocation" {
    type    = "string"
    default = "East US"
}
