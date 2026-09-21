# Provider requirements for the network module.
#
# A reusable module pins its own provider constraint so that standalone
# `terraform validate` inside the module resolves the same major version the
# root module uses (root providers.tf pins hashicorp/aws ~> 5.0). Without this
# a bare `terraform init` here could resolve a v6.x provider and validate
# against a schema the root will never actually use.
#
# NOTE: no `provider "aws"` block is declared here on purpose. Modules must
# inherit the provider (and therefore the region and default_tags) configured
# by the root module.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
