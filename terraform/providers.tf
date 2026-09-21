# Provider configuration for the dev environment root module
#
# NOTE: no remote backend is configured here. State is local for now.
# Before this project is shared or applied by more than one operator, add an
# S3 backend + DynamoDB state locking. Tracked as a follow-up.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Used to generate the RDS master password. Credentials are never
    # hardcoded in .tf files (see CLAUDE.md section 4).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Credentials are supplied by the environment (AWS_PROFILE / AWS_ACCESS_KEY_ID
# / instance role). Never hardcode credentials, profiles, or account IDs here.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
