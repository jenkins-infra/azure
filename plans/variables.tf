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
  type    = "string"
  default = "Standard_D2_v2"
}

# Define default ssh public key path used to provision new kubernetes agent
variable "ssh_pubkey_path" {
  type    = "string"
  default = "./ssh_key/id_rsa.pub"
}

variable "logslocation" {
  type    = "string"
  default = "East US"
}

# This variable is only use to trigger a new confluence database password
variable "confluence_db_password_id" {
  type    = "string"
  default = "2018082402"
}

# This variable is used to trigger a new uplink database password
variable "uplink_db_password_id" {
  type    = "string"
  default = "2018091501"
}
