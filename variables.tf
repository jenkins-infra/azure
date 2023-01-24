variable "location" {
  type    = string
  default = "East US 2"
}

# TODO: remove this and hardcode it in concerned tf files
variable "kubernetes_version" {
  type    = string
  default = "1.23.12"
}
