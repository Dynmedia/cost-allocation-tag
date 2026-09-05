aws_profile           = "mgt"
management_account_id = "660571558619"

# A GitHub OIDC provider already exists in this account -> reuse it.
reuse_existing_oidc_provider = true

github_org  = "Dynmedia"
github_repo = "cost-allocation-tag"

allowed_branches = ["main"]

state_bucket_name  = "dyn-tfstate-ai-cost-660571558619"
pipeline_role_name = "gha-ai-cost-deployer"
