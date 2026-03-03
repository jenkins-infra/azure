variable "location" {
  type    = string
  default = "East US 2"
}

variable "cert_ci_location" {
  type    = string
  default = "Sweden Central"
}

variable "terratest" {
  type        = bool
  description = "value"
  default     = false
}
