output "deployed_in_account" {
  value = data.aws_caller_identity.current.account_id
}

output "activated_cost_allocation_tags" {
  value = sort([for t in aws_ce_cost_allocation_tag.activated : t.tag_key])
}

output "ai_cost_category_arn" {
  value = aws_ce_cost_category.ai_attribution.arn
}

output "developer_budget" {
  value = aws_budgets_budget.ai_developer.name
}

output "product_budget" {
  value = aws_budgets_budget.ai_product.name
}

output "notes" {
  value = <<-EOT
    - Cost Category "AICostAttribution" groups spend into developer/product by
      LINKED_ACCOUNT. See it in Cost Explorer (group by Cost Category), ~24h.
    - Budgets filter by LinkedAccount, so they track TOTAL account spend, not
      only AI. Only put accounts here whose spend is predominantly AI.
    - When taggable AI infra exists: tag it aiworkload=developer|product|platform,
      then set enable_aiworkload_activation + enable_aiworkload_category_rules.
  EOT
}
