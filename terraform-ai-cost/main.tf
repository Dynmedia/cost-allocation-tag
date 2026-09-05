###############################################################################
# 1. Activate cost allocation tags
#    Makes the tag keys your Config policy enforces (plus AI) usable as cost
#    dimensions in Cost Explorer and Budgets. Applies org-wide via the payer.
###############################################################################
resource "aws_ce_cost_allocation_tag" "activated" {
  for_each = toset(var.cost_allocation_tag_keys)
  tag_key  = each.value
  status   = "Active"
}

###############################################################################
# 2. "AI" Cost Category
#    A single durable dimension = (resources tagged AI=true)
#                              OR (known AI services / models).
#    This closes the gap where AI cost is usage-based and has no taggable
#    resource (on-demand Bedrock invocations, Kiro, etc.).
###############################################################################
resource "aws_ce_cost_category" "ai" {
  name         = "AI"
  rule_version = "CostCategoryExpression.v1"

  # Rule A: anything explicitly tagged AI=true.
  # Guarded by var.enable_ai_tag_rule: only include this once the AI tag has
  # been ACTIVATED as a cost allocation tag (which itself requires the tag to
  # exist on at least one resource). Until then, tag-based matching isn't
  # available and the category runs on the SERVICE_CODE rules below.
  dynamic "rule" {
    for_each = var.enable_ai_tag_rule ? [1] : []
    content {
      value = "AI"
      rule {
        tags {
          key           = var.ai_tag_key
          values        = [var.ai_tag_true_value]
          match_options = ["EQUALS"]
        }
      }
    }
  }

  # Rule B: known AI services matched by SERVICE_CODE substring.
  # Cost Categories only allow SERVICE_CODE (not the friendly SERVICE name), and
  # CONTAINS keeps this stable as AWS adds new Bedrock model line items
  # (their codes all contain "Bedrock").
  dynamic "rule" {
    for_each = var.ai_service_code_contains
    content {
      value = "AI"
      rule {
        dimension {
          key           = "SERVICE_CODE"
          values        = [rule.value]
          match_options = ["CONTAINS"]
        }
      }
    }
  }

  # Everything else falls through to this bucket.
  default_value = "Non-AI"
}

###############################################################################
# 3. Budget on the AI Cost Category  -> runaway-spend guardrail
#    Scoped by the Cost Category value "AI" so it tracks TOTAL AI spend
#    (tagged resources + AI services), not a single service.
###############################################################################
resource "aws_budgets_budget" "ai" {
  name         = var.budget_name
  budget_type  = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Cost Category filter format is "CategoryName$Value". The category is named
  # "AI" and the value we bucket AI spend under is also "AI" -> "AI$AI".
  # "$$" escapes to a literal "$" in an HCL interpolation string.
  cost_filter {
    name   = "CostCategories"
    values = ["${aws_ce_cost_category.ai.name}$$AI"]
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

  depends_on = [aws_ce_cost_category.ai]
}
