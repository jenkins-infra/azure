variable "name" {
  description = "Unique name for all resources to create"
}

variable "pls_name" {
  description = "Name of the Azure Private Link Service (PLS) to target"
  type        = string
}

variable "pls_rg_name" {
  description = "Name of the Resource Group of the Azure Private Link Service (PLS) targeted by 'var.pls_name'"
  type        = string
}

variable "rg_name" {
  description = "Name of the Resource Group in which to create other resources (not PLS, not DNS)"
  type        = string
}

variable "dns_rg_name" {
  description = "Name of the Resource Group in which to create DNS resources"
  type        = string
}

variable "location" {
  description = "Which Azure Location toi use foi all resources?"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet to associate with the PE and DNS resources"
  type        = string
}

variable "vnet_id" {
  description = "ID of the virtual network to associate with the PE and DNS resources (contains subnet which ID is 'var.subnet_id')"
  type        = string
}

variable "fqdn" {
  description = "FQDN for the private DNS zone"
  type        = string
}

variable "default_tags" {
  description = "Map of tags to set up for resource which permit it"
  type        = map(string)
}

variable "dns_a_record" {
  description = "Name of the DNS A record to create, pointing to the PE"
  type        = string
}

variable "dns_zone_name" {
  description = "Name of an existing private DNS zone you want to use instead of creating a new one"
  type        = string
  default     = ""
}
