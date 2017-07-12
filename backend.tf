# Terraform 0.9 is designed to find all data it needs at the root of the project and 
# do not yet support something like 'terraform init plan_directory'.
# This feature is introduced in v 0.10

# In order to keep the project architecture as is, we just add a second backend declaration
# at the root of the project and we'll delete this file once we upgrade to 0.10

# doc: https://www.terraform.io/docs/backends/config.html
# issue: https://github.com/hashicorp/terraform/issues/14066
# https://github.com/hashicorp/terraform/blob/master/CHANGELOG.md#0100-beta1-june-22-2017

terraform {
  backend "azure" {}
}
