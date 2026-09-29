variable "aws_profile" {
  description = "AWS CLI profile for the MANAGEMENT account (payer). Empty in CI (OIDC)."
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
    LOWERCASE standard tag keys to ACTIVATE as cost allocation tags so they
    appear in Cost Explorer. Matches the org tag policy and the AWS Config
    REQUIRED_TAGS rule (keys are lowercase since Sep 2026), plus product.

    Billing tag keys are CASE-SENSITIVE: "owner" and "Owner" are two separate
    cost allocation tags.

    NOTE: A key can only be activated AFTER AWS Billing has seen it on a
    resource, otherwise the apply fails. Not listed yet (Billing hasn't seen
    them as of 2026-09-30): "costcenter", "stage". Add each one once
    `aws ce list-cost-allocation-tags --tag-keys <key>` (us-east-1, management
    account) returns it. "aiworkload" is handled by enable_aiworkload_activation.
  EOT
  type        = list(string)
  default = [
    "owner",
    "environment",
    "project",
    "team",
    "product",
  ]
}

variable "legacy_cost_allocation_tag_keys" {
  description = <<-EOT
    PascalCase keys from the pre-Sep-2026 standard. Kept ACTIVE during the
    migration so spend on resources that still carry them stays attributable and
    existing Cost Explorer reports keep working. Removing a key here DEACTIVATES
    it (new costs stop being grouped under it; history is kept). Remove once no
    resource uses the old spelling.
  EOT
  type        = list(string)
  default = [
    "Owner",
    "Environment",
    "Project",
    "CostCenter",
    "Stage",
    "Team",
    "Product",
  ]
}

# --- Account-based AI attribution (works TODAY) -----------------------------
# Your AI spend is usage-shaped (Kiro subscription + on-demand Bedrock), so it
# has almost no taggable resource. LINKED_ACCOUNT is the dimension that actually
# carries the signal, so the Cost Category + budgets attribute AI cost by which
# account incurs it. Edit these lists to remap; removing an account is one line.
variable "ai_developer_accounts" {
  description = "Linked account IDs whose AI spend is developer/tooling."
  type        = map(string) # id => human label (label is just for readability)
  default = {
    "660571558619" = "dyn media (Kiro)"
    "982081082306" = "dyn-api-toolkit-dev"
    "905418363445" = "dyn-generate-article-dev"
    "920263653563" = "dyn-connect-dev"
    "400398152715" = "dyn-connect-staging"
    "893945595122" = "sandbox-fabian"
    "905418329225" = "sandbox-niklas"
  }
}

variable "ai_product_accounts" {
  description = "Linked account IDs whose AI spend is product (customer-facing)."
  type        = map(string)
  default = {
    "381492097421" = "dyn-generate-article-prod"
    "660249532472" = "dyn-connect-prod"
    "122610502176" = "dyn-api-toolkit-prod"
  }
}

# --- aiworkload classification tag (forward-looking) ------------------------
variable "aiworkload_tag_key" {
  description = "Tag key for classifying taggable AI resources when they exist."
  type        = string
  default     = "aiworkload"
}

variable "enable_aiworkload_activation" {
  description = <<-EOT
    Activate aiworkload as a cost allocation tag. Keep false until at least one
    resource is tagged aiworkload=... (AWS rejects activating an unseen key).
  EOT
  type        = bool
  default     = false
}

variable "enable_aiworkload_category_rules" {
  description = <<-EOT
    Add aiworkload tag rules to the Cost Category (developer/product). Keep false
    until the tag exists; account-based rules carry attribution until then.
  EOT
  type        = bool
  default     = false
}

# --- Budgets ----------------------------------------------------------------
# IMPORTANT: a budget's LinkedAccount filter captures TOTAL account spend, not
# just AI. So the budget account sets must EXCLUDE accounts with large non-AI
# cost (notably the management account 660571558619, whose $18k/mo is mostly
# shared org cost, not its $1.4k Kiro). These sets are therefore narrower than
# the Cost Category account sets. Kiro is tracked via the Cost Category, not the
# developer budget.
variable "developer_budget_accounts" {
  description = "Accounts for the developer budget (predominantly-AI accounts only)."
  type        = map(string)
  default = {
    "982081082306" = "dyn-api-toolkit-dev"
    "905418363445" = "dyn-generate-article-dev"
    "920263653563" = "dyn-connect-dev"
    "400398152715" = "dyn-connect-staging"
    "893945595122" = "sandbox-fabian"
    "905418329225" = "sandbox-niklas"
  }
}

variable "product_budget_accounts" {
  description = "Accounts for the product budget (predominantly-AI accounts only)."
  type        = map(string)
  default = {
    "381492097421" = "dyn-generate-article-prod"
    "660249532472" = "dyn-connect-prod"
    "122610502176" = "dyn-api-toolkit-prod"
  }
}

variable "developer_budget_amount" {
  description = "Monthly ceiling (USD) for developer AI spend."
  type        = string
  default     = "5000"
}

variable "product_budget_amount" {
  description = "Monthly ceiling (USD) for product AI spend."
  type        = string
  default     = "5000"
}

variable "notify_emails" {
  description = "Emails that receive AI budget overrun alerts."
  type        = list(string)
  # No default: force a real address at apply time (CI passes TF_VAR_notify_emails).
}

variable "actual_thresholds_percent" {
  type    = list(number)
  default = [80, 100]
}

variable "forecasted_thresholds_percent" {
  type    = list(number)
  default = [100]
}
