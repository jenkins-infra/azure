variable "subscription_id" {}
variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}
variable "prefix" {}

variable "location" {
    type    = "string"
    default = "East US 2"
}

# Port used for Puppet agents to connect to a Puppet master
variable "puppet_master_port" {
    default = 8140
}


# Project Analytics
###################
# Valid options are between 1 and 7, see:
#   <https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-faq#what-is-the-maximum-retention-period>
variable "analytics_eventhub_retention_days" {
    default = 1
}
# Four is the default number of partitions, codifying it here for posterity
# however. See:
#   <https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-overview>
variable "analytics_eventhub_partitions" {
    default = 4
}

#   <https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-faq#what-are-event-hubs-throughput-units>
variable "project_analytics_throughput" {
    default = 1
}
###################
#
