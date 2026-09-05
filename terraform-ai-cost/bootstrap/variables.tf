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

variable "state_bucket_name" {
  description = "S3 bucket for the AI-cost module's remote Terraform state."
  type        = string
  # Must be globally unique. Account-id suffix keeps it unique + traceable.
  default = "dyn-tfstate-ai-cost-660571558619"
}

variable "github_org" {
  description = "GitHub org/owner that hosts the repo."
  type        = string
  default     = "Dynmedia"
}

variable "github_repo" {
  description = "GitHub repository name (without owner)."
  type        = string
  default     = "cost-allocation-tag"
}

variable "allowed_branches" {
  description = "Branches allowed to assume the role (used in the OIDC sub claim)."
  type        = list(string)
  default     = ["main"]
}

variable "pipeline_role_name" {
  type    = string
  default = "gha-ai-cost-deployer"
}

variable "reuse_existing_oidc_provider" {
  description = <<-EOT
    Set true if the management account ALREADY has a GitHub Actions OIDC provider
    (token.actions.githubusercontent.com). An account can only have one provider
    per URL, so creating a second fails. Detect with:
      aws iam list-open-id-connect-providers --profile mgt
  EOT
  type        = bool
  default     = false
}
