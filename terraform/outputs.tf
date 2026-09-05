output "budget_name" {
  value = aws_budgets_budget.q_agent.name
}

output "activated_cost_allocation_tags" {
  value = [for t in aws_ce_cost_allocation_tag.this : t.tag_key]
}

output "budget_cost_filter" {
  description = "The tag filter the budget tracks."
  value       = "user:${var.cost_filter_tag_key}$${var.cost_filter_tag_value}"
}
