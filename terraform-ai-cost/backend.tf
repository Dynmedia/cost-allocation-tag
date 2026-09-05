###############################################################################
# Remote state for the AI-cost module.
#
# The S3 bucket is created by ./bootstrap (apply that FIRST). After bootstrap,
# migrate local state into S3:
#
#   terraform init -migrate-state
#
# Uses S3 native locking (use_lockfile) instead of a DynamoDB table, supported
# in AWS provider / Terraform 1.10+.
###############################################################################
terraform {
  backend "s3" {
    bucket       = "dyn-tfstate-ai-cost-660571558619"
    key          = "ai-cost/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
    # No `profile` here on purpose:
    #   - CI: credentials come from OIDC (env vars) -> no profile needed.
    #   - Local: pass it at init time ->
    #       terraform init -migrate-state -backend-config="profile=mgt"
  }
}
