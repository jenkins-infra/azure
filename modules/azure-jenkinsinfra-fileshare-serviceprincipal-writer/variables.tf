# Required variables
variable "service_fqdn" {
  type = string
}

variable "active_directory_owners" {
  type = list(string)
}

variable "active_directory_url" {
  type = string
}

variable "service_principal_end_date" {
  type = string
}

variable "file_share_id" {
  type = string
}

variable "storage_account_id" {
  type = string
}

# Optional variables
variable "default_tags" {
  type    = map(string)
  default = {}
}
