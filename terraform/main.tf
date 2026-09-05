###############################################################################
# Amazon Q Agent cost governance as code.
#
# Provides the repeatable, reviewable path for acceptance criteria #2 and #3:
#   * Activate user-defined cost allocation tags (visible in Cost Explorer)
#   * Create an AWS Budget with actual + forecasted overrun alerts
#
# Budgets and cost allocation tags are global; pin the provider to us-east-1.
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
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

# --- Cost allocation tag activation ----------------------------------------
# Marks user-defined tag keys as active cost allocation tags so they surface in
# Cost Explorer and can be used as budget filters.
resource "aws_ce_cost_allocation_tag" "this" {
  for_each  = toset(var.cost_allocation_tag_keys)
  tag_key   = each.value
  status    = "Active"
}

# --- Budget with overrun alerts ---------------------------------------------
resource "aws_budgets_budget" "q_agent" {
  name         = var.budget_name
  budget_type  = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = var.budget_limit_unit
  time_unit    = "MONTHLY"

  # Scope the budget to the tagged Amazon Q Agent workload.
  # The literal separator between key and value is a single "$", which must be
  # escaped as "$$" in an HCL interpolation string.
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:${var.cost_filter_tag_key}$$${var.cost_filter_tag_value}"]
  }

  # Alert when ACTUAL spend crosses each threshold.
  dynamic "notification" {
    for_each = var.actual_thresholds_percent
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.notify_emails
    }
  }

  # Alert when FORECASTED spend is expected to cross each threshold.
  dynamic "notification" {
    for_each = var.forecasted_thresholds_percent
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = var.notify_emails
    }
  }

  depends_on = [aws_ce_cost_allocation_tag.this]
}
