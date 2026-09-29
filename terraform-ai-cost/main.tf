###############################################################################
# 1. Activate cost allocation tags
#    Makes the standard tag keys (+ product) usable as cost dimensions in Cost
#    Explorer and budgets. Applies org-wide via the payer.
#
#    Both spellings are active during the lowercase migration: the lowercase
#    standard keys and the legacy PascalCase keys (case-sensitive in Billing).
#
#    aiworkload is activated only when enable_aiworkload_activation = true
#    (a key can't be activated until AWS has seen it on a resource).
###############################################################################
locals {
  activation_keys = concat(
    var.cost_allocation_tag_keys,
    var.legacy_cost_allocation_tag_keys,
    var.enable_aiworkload_activation ? [var.aiworkload_tag_key] : [],
  )

  developer_account_ids = keys(var.ai_developer_accounts)
  product_account_ids   = keys(var.ai_product_accounts)

  # Budget account sets are narrower (exclude big non-AI accounts like mgmt).
  developer_budget_account_ids = keys(var.developer_budget_accounts)
  product_budget_account_ids   = keys(var.product_budget_accounts)
}

resource "aws_ce_cost_allocation_tag" "activated" {
  for_each = toset(local.activation_keys)
  tag_key  = each.value
  status   = "Active"
}

###############################################################################
# 2. "AICostAttribution" Cost Category
#    One durable dimension bucketing AI spend into "developer" / "product".
#
#    Primary lever = LINKED_ACCOUNT (your AI spend is usage-shaped: Kiro
#    subscription + on-demand Bedrock, with almost no taggable resource, so the
#    account is what actually carries the signal).
#
#    Optionally ALSO match the aiworkload tag once tagging is live, so tagged
#    resources are classified even if they sit in a "mixed" account.
###############################################################################
resource "aws_ce_cost_category" "ai_attribution" {
  name         = "AICostAttribution"
  rule_version = "CostCategoryExpression.v1"

  # developer: by account
  rule {
    value = "developer"
    rule {
      dimension {
        key           = "LINKED_ACCOUNT"
        values        = local.developer_account_ids
        match_options = ["EQUALS"]
      }
    }
  }

  # product: by account
  rule {
    value = "product"
    rule {
      dimension {
        key           = "LINKED_ACCOUNT"
        values        = local.product_account_ids
        match_options = ["EQUALS"]
      }
    }
  }

  # developer: by aiworkload tag (optional, once tag exists)
  dynamic "rule" {
    for_each = var.enable_aiworkload_category_rules ? [1] : []
    content {
      value = "developer"
      rule {
        tags {
          key           = var.aiworkload_tag_key
          values        = ["developer"]
          match_options = ["EQUALS"]
        }
      }
    }
  }

  # product: by aiworkload tag (optional, once tag exists)
  dynamic "rule" {
    for_each = var.enable_aiworkload_category_rules ? [1] : []
    content {
      value = "product"
      rule {
        tags {
          key           = var.aiworkload_tag_key
          values        = ["product"]
          match_options = ["EQUALS"]
        }
      }
    }
  }

  # Everything else (non-AI accounts, untagged) falls here.
  default_value = "unclassified"
}

###############################################################################
# 3. Budgets — one per AI category, each a runaway-spend guardrail.
#    Filtered by the SAME account sets that define the Cost Category, so the
#    budget and the reporting view agree.
###############################################################################
resource "aws_budgets_budget" "ai_developer" {
  name         = "ai-developer-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.developer_budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = local.developer_budget_account_ids
  }

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
}

resource "aws_budgets_budget" "ai_product" {
  name         = "ai-product-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.product_budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = local.product_budget_account_ids
  }

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
}
