variable "aws_profile" {
  description = "AWS CLI profile for the MANAGEMENT account (payer)."
  type        = string
  default     = "mgt"
}

variable "management_account_id" {
  description = "Org management/payer account ID. Guards against applying elsewhere."
  type        = string
  default     = "660571558619"
}

# --- Cost allocation tag activation -----------------------------------------
variable "cost_allocation_tag_keys" {
  description = <<-EOT
    User-defined tag keys to ACTIVATE as cost allocation tags so they appear in
    Cost Explorer. Mirrors the keys your AWS Config policy enforces.

    NOTE: A key can only be activated AFTER AWS has seen it on at least one
    resource. "AI" is intentionally NOT here yet, because no resource is tagged
    AI=... in the org. Add "AI" once the tag policy has tagged something (and
    flip enable_ai_tag_rule to true).
  EOT
  type        = list(string)
  default = [
    "Owner",
    "Environment",
    "Project",
    "CostCenter",
    "Stage",
    "Team",
  ]
}

# --- AI classification tag ---------------------------------------------------
variable "ai_tag_key" {
  description = "Tag key used to classify AI resources."
  type        = string
  default     = "AI"
}

variable "ai_tag_true_value" {
  description = "Tag value that marks a resource as AI-related."
  type        = string
  default     = "true"
}

variable "enable_ai_tag_rule" {
  description = <<-EOT
    Include the AI=true tag rule in the Cost Category. Keep false until the AI
    tag actually exists on resources; otherwise the category still works on the
    SERVICE_CODE rules below. Flip to true once AI tagging is live.
  EOT
  type        = bool
  default     = false
}

# --- AI service classification (catches usage-based AI spend w/o resources) --
variable "ai_service_code_contains" {
  description = <<-EOT
    Substrings matched against SERVICE_CODE (Cost Categories don't allow the
    friendly SERVICE name). CONTAINS keeps rules stable as AWS adds new Bedrock
    model line items (their service codes all contain "Bedrock").
    Examples of SERVICE_CODE: AmazonBedrock, AmazonSageMaker, AmazonLex,
    AmazonPolly.
  EOT
  type        = list(string)
  default = [
    "Bedrock",   # AmazonBedrock, Bedrock AgentCore, and all Bedrock-Edition models
    "SageMaker", # AmazonSageMaker
    "Kiro",      # Kiro
    "Lex",       # AmazonLex
    "Polly",     # AmazonPolly
  ]
}

# --- Budget / alerts ---------------------------------------------------------
variable "budget_name" {
  type    = string
  default = "ai-spend-monthly-budget"
}

variable "budget_limit_amount" {
  description = "Monthly AI budget ceiling (string, USD)."
  type        = string
  # Current AI spend ~ $2,100/mo (Kiro ~1,462 + Bedrock family ~600).
  # Set the ceiling above current run-rate so alerts flag GROWTH, not steady state.
  default = "3000"
}

variable "notify_emails" {
  description = "Emails that receive AI budget overrun alerts."
  type        = list(string)
  # No default on purpose: force a real address at apply time.
}

variable "actual_thresholds_percent" {
  type    = list(number)
  default = [80, 100]
}

variable "forecasted_thresholds_percent" {
  type    = list(number)
  default = [100]
}
