output "deployed_in_account" {
  description = "Account these billing resources were created in (must be the payer)."
  value       = data.aws_caller_identity.current.account_id
}

output "activated_cost_allocation_tags" {
  value = sort([for t in aws_ce_cost_allocation_tag.activated : t.tag_key])
}

output "ai_cost_category_arn" {
  value = aws_ce_cost_category.ai.arn
}

output "ai_budget_name" {
  value = aws_budgets_budget.ai.name
}

output "next_steps" {
  value = <<-EOT
    1. Cost allocation tags can take up to ~24h to appear in Cost Explorer.
    2. In Cost Explorer, group by "Cost Category: AI" to see AI vs Non-AI spend.
    3. Confirm the SNS/email budget subscription if prompted.
    4. Extend the AWS Config module (security acct 754348400096) so the "AI" tag
       is governed org-wide (recommend an Organizations Tag Policy with allowed
       values true/false rather than making it a required tag).
  EOT
}
