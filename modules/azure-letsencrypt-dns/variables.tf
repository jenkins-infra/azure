variable "default_tags" {
  type        = map(string)
  description = "Map of tags to be applied to resources"
}

variable "zone_name" {
  type        = string
  description = "Name of the DNS zone handling the Let's Encrypt renewal"
}

variable "principal_id" {
  type        = string
  description = "ID of the Identity used to manage DNS records for Let's Encrypt (usually the Service Principal ID)"
}

variable "dns_rg_name" {
  type        = string
  description = "Name of the Resource Group in which to create the DNZ zone"
}

variable "parent_zone_name" {
  type        = string
  description = "Name of the 'parent' DNS zone (in which to create NS records for the child zone)"
}
