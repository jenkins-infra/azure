variable "name" {
  type        = string
  description = "Unique name to use for the created resources."
}

variable "acr_name" {
  type        = string
  description = "Name of the Azure Container Registry to (privately) link to."
}

variable "acr_rg_name" {
  type        = string
  description = "Name of the Resource Group containing the Azure Container Registry to (privately) link to."
}

variable "acr_location" {
  type        = string
  description = "Azure location of the Azure Container Registry to (privately) link to."
}

variable "default_tags" {
  type        = map(string)
  description = "Map of tags to be applied to resources."
}

variable "vnet_rg_name" {
  type        = string
  description = "Name of the Resource Group containing the virtual network and the subnet to use."
}

variable "vnet_name" {
  type        = string
  description = "Name of the Virtual Network to use."
}

variable "subnet_name" {
  type        = string
  description = "ID of the Subnet to use."
}

variable "private_dns_zone_id" {
  type        = string
  default     = ""
  description = "(optional) ID of the Private DNS Zone to use"

}
