###############################################################################
# AI Cost Visibility - deploys to the ORG MANAGEMENT (payer) account only.
#
#   Management account: 660571558619 (dyn media)
#
# Cost allocation tag activation, Cost Categories, and Budgets are payer-level
# billing features -> they can ONLY be created in the management account, and
# they automatically apply across all linked accounts via consolidated billing.
#
# This is intentionally separate from the AWS Config tagging module, which lives
# in the security account (754348400096). That module ENFORCES that tags exist
# on resources; this module makes those tags VISIBLE in Cost Explorer and adds
# spend guardrails. They connect only through the shared tag key strings.
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
  # Billing/Cost Explorer/Budgets/Cost Categories are global services reached
  # through us-east-1, regardless of where workloads run.
  region = "us-east-1"

  # Local runs set aws_profile="mgt"; CI leaves it empty so OIDC env creds win.
  profile = var.aws_profile != "" ? var.aws_profile : null

  # Safety rail: refuse to apply unless we are in the management account.
  allowed_account_ids = [var.management_account_id]
}

data "aws_caller_identity" "current" {}
