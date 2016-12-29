#
# This terraform plan defines the resources necessary to provision Azure
# project_analytics applications which will perform various tasks for the Jenkins
# project.
#
# This repository should not store these project_analytics, but rather provision the
# infrastructure such that project_analytics can be deployed from:
#   https://github.com/jenkins-infra/project_analytics


resource "azurerm_resource_group" "project_analytics" {
    name     = "${var.prefix}-project-analytics"
    location = "${var.location}"
    tags {
        env = "${var.prefix}"
    }
}

resource "azurerm_eventhub_namespace" "project_analytics" {
    name                = "project-analytics"
    location            = "${azurerm_resource_group.project_analytics.location}"
    resource_group_name = "${azurerm_resource_group.project_analytics.name}"
    sku                 = "Standard"
    capacity            = "${var.project_analytics_throughput}"
    tags {
        env = "${var.prefix}"
    }
}

# RESOURCES FOR GITHUB EVENTS PROCESSING
################################################################################
resource "azurerm_eventhub" "github_events" {
    name                = "github-events"
    namespace_name      = "${azurerm_eventhub_namespace.project_analytics.name}"
    location            = "${azurerm_resource_group.project_analytics.location}"
    resource_group_name = "${azurerm_resource_group.project_analytics.name}"
    partition_count     = "${var.analytics_eventhub_partitions}"
    message_retention   = "${var.analytics_eventhub_retention_days}"
}

resource "azurerm_template_deployment" "jenkinsci_events_db" {
    name                = "github-events-jenkinsci"
    resource_group_name = "${azurerm_resource_group.project_analytics.name}"
    depends_on          = ["azurerm_resource_group.project_analytics"]
    parameters          = {
        databaseAccountName = "github-events-jenkinsci"
    }
    deployment_mode     = "Incremental"
    template_body       = "${file("./arm_templates/documentdb.json")}"
}

resource "azurerm_template_deployment" "jenkinsinfra_events_db" {
    name                = "github-events-jenkins-infra"
    resource_group_name = "${azurerm_resource_group.project_analytics.name}"
    depends_on          = ["azurerm_resource_group.project_analytics"]
    parameters          = {
        databaseAccountName = "github-events-jenkins-infra"
    }
    deployment_mode     = "Incremental"
    template_body       = "${file("./arm_templates/documentdb.json")}"
}

resource "azurerm_template_deployment" "github-event-function" {
    name                = "${var.prefix}-github-event-function"
    resource_group_name = "${azurerm_resource_group.project_analytics.name}"
    depends_on          = [
        "azurerm_resource_group.project_analytics",
        "azurerm_eventhub.github_events",
    ]
    parameters          = {
        appName = "github-events",
    }
    deployment_mode     = "Incremental"
    template_body       = "${file("./arm_templates/github-events-function.json")}"
}
################################################################################
