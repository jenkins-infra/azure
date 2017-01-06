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
    default = "Standard_A2"
}
# Define default ssh public key used to provision new kubernetes agent
variable "ssh_pubkey" {
    type = "string"
    default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC4Bvn9TvicSk/fBKHqMqSyR95FbPV+Ie2TJS9grKO7UByHErsSM5Pz1i9DO4l0LDma8vIaj/zn1RIN38Q96xwWd7dfWalmvZm3/hX5z5UW/KiVfla/BmltFZFwCtl6XjbDEtnkLMp+pMDzpbA8tbLOI23SQAj0R5XlmKGV8NluKGhFCTLQYWNIjoCdpYITOP7ibLDd3C9TzL1pucgbBG8R+/c1ijDkRhPUNj4s4jjawQ4rnSAj5Hm7jHQ93Bg2TiYjp3DoEGBtNjQoVbF+0ZbGQOydHj0QMhsle83nEjfdCahg21BquOW7kHV0gxPQs4LlpISKGhZ96yFqIgStUu2Z example@sshpublickey"
}
