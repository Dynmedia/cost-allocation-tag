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
    Cost Explorer. Should mirror the keys your AWS Config policy enforces, plus
    the AI classification tag.
  EOT
  type        = list(string)
  default = [
    "Owner",
    "Environment",
    "Project",
    "CostCenter",
    "Stage",
    "Team",
    "AI",
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

# --- AI service classification (catches usage-based AI spend w/o resources) --
variable "ai_service_exact_matches" {
  description = "Exact SERVICE names on the bill to classify as AI."
  type        = list(string)
  default = [
    "Kiro",
    "Amazon SageMaker",
    "Amazon Lex",
    "Amazon Polly",
    "AWSDevOpsAgent",
    "Q in Connect",
  ]
}

variable "ai_service_contains_matches" {
  description = <<-EOT
    Substrings matched against SERVICE names to classify as AI. Using CONTAINS
    keeps the rule stable as AWS adds new Bedrock model line items (e.g. new
    Claude/Cohere/Stable "Amazon Bedrock Edition" entries).
  EOT
  type        = list(string)
  default = [
    "Bedrock", # Amazon Bedrock, Amazon Bedrock AgentCore, and all "(Amazon Bedrock Edition)" models
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
