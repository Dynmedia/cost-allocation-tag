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
    The CURRENT standard tag keys to ACTIVATE as cost allocation tags, so they
    appear in Cost Explorer. Matches the org tag policy (p-957g5s40o6) and the
    AWS Config REQUIRED_TAGS rule: PascalCase with a `Dyn-` prefix since
    Oct 2026, except `Owner`, which carries no prefix. Plus the pre-existing
    `product` key, which is not part of the tagging standard.

    Billing tag keys are CASE-SENSITIVE: "Dyn-Team", "dyn-team" and "team" are
    three separate cost allocation tags. That is why the superseded spellings
    are kept in legacy_cost_allocation_tag_keys rather than edited in place.

    NOTE: a key can only be activated AFTER AWS Billing has seen it on a real
    resource; activating an unseen key fails the apply. All five Dyn- keys
    below were live-verified as seen (Inactive, lastUsed 2026-10-01) on
    2026-10-08, roughly a day after security-account#49 retagged its own
    resources.

    `Dyn-AIWorkload` is deliberately NOT here: Billing has still never seen it,
    because no AI resource carries it yet. It is handled separately by
    enable_aiworkload_activation. Check with:
      aws ce list-cost-allocation-tags --tag-keys Dyn-AIWorkload \
        --region us-east-1 --profile mgt
  EOT
  type        = list(string)
  default = [
    "Owner",
    "Dyn-Environment",
    "Dyn-Project",
    "Dyn-CostCenter",
    "Dyn-Stage",
    "Dyn-Team",
    "product",
  ]
}

variable "legacy_cost_allocation_tag_keys" {
  description = <<-EOT
    Superseded key spellings to keep ACTIVE as cost allocation tags during a
    migration, so spend on resources that still carry them stays groupable in
    Cost Explorer.

    EMPTY as of 2026-10-10: every superseded spelling has now been
    deactivated by request, in two steps.

      1. The all-lowercase generation ("owner", "environment", "project",
         "team") -- then on ~4,657 / ~5,744 / 185 / 17 resources.
      2. The original PascalCase generation ("Environment", "Project",
         "CostCenter", "Stage", "Team", "Product") -- then on 270 / 315 / 32
         / 1 / 1 / 24 resources.

    So roughly 11,000 resources' spend no longer groups by any tag, because
    the resources carrying those keys have not been retagged to the `Dyn-`
    standard (only ~25 resources org-wide carried `Dyn-*` at the time).
    Historical cost data under the old keys is retained; only NEW costs stop
    being grouped. Retagging the workloads -- DCC's CDK app above all -- is
    what restores grouping, not re-activating keys here.

    Re-adding a spelling reactivates it, so both steps are reversible.
    "costcenter", "stage" and the lowercase "dyn-*" spellings were never
    activated at all: Billing has never seen them on a resource, and
    activating an unseen key fails the apply.
  EOT
  type        = list(string)
  default     = []
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
