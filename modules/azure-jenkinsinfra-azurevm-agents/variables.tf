# Required variables
variable "service_fqdn" {
  type = string
}

variable "service_short_stripped_name" {
  type = string
}

variable "ephemeral_agents_network_name" {
  type = string
}

variable "ephemeral_agents_network_rg_name" {
  type = string
}

variable "nsg_rg_name" {
  type        = string
  description = "Name of the Resource Group where to create the Network Security Group (unneeded if var.use_vnet_common_nsg is true)."
  default     = ""
}

variable "ephemeral_agents_subnet_name" {
  type = string
}

variable "controller_ips" {
  type = list(string)
}

variable "controller_service_principal_id" {
  type        = string
  description = "The controller Azure identity ID which can manage Azure VM agents."
}

variable "default_tags" {
  type    = map(string)
  default = {}
}

variable "jenkins_infra_ips" {
  type = object({
    privatevpn_subnet = list(string)
  })
}

variable "custom_resourcegroup_name" {
  type    = string
  default = ""
}

variable "storage_account_name" {
  type    = string
  default = ""
}

variable "additional_identities" {
  type        = list(string)
  description = "A list of Azure identity IDs, in addition to controller_service_principal_id, which can manage Azure VM agents."
  default     = []
}

variable "use_vnet_common_nsg" {
  type        = bool
  description = "Should we use the Network Security Group ('NSG') located in the same Resource Group as the provided Virtual Network and with the same name (convention)?"
  default     = false
}
