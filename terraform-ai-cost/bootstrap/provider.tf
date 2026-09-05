###############################################################################
# Bootstrap for the AI-cost CI/CD pipeline.
#
# Creates the prerequisites the GitHub Actions pipeline needs, in the ORG
# MANAGEMENT account (660571558619):
#   1. S3 bucket for remote Terraform state (with native S3 locking)
#   2. GitHub OIDC identity provider
#   3. A scoped IAM role the workflow assumes via OIDC (no long-lived keys)
#
# Apply this ONCE, locally, with the `mgt` profile. After that the pipeline
# uses the outputs (state bucket + role ARN). Bootstrap keeps LOCAL state on
# purpose (chicken-and-egg: it creates the very bucket remote state would live
# in), so commit its terraform.tfstate or re-apply is idempotent.
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

provider "aws" {
  region              = "us-east-1"
  profile             = var.aws_profile
  allowed_account_ids = [var.management_account_id]
}

data "aws_caller_identity" "current" {}
