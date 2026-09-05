###############################################################################
# 1. Remote state bucket
###############################################################################
resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Guardrail against accidental deletion of the state bucket.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# 2. GitHub OIDC identity provider
#    Reuse an existing provider if the account already has one (common in
#    orgs that already use GitHub Actions OIDC).
###############################################################################
data "aws_iam_openid_connect_provider" "existing_github" {
  count = var.reuse_existing_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.reuse_existing_oidc_provider ? 0 : 1
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint is validated by AWS via the JWKS; this value is a
  # well-known fallback. AWS no longer strictly requires an accurate thumbprint
  # for token.actions.githubusercontent.com, but the field is still mandatory.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  oidc_provider_arn = var.reuse_existing_oidc_provider ? data.aws_iam_openid_connect_provider.existing_github[0].arn : aws_iam_openid_connect_provider.github[0].arn

  # Subject claims allowed to assume the role:
  #  - each protected branch (for apply on merge)
  #  - pull_request context (for plan on PRs)
  allowed_subs = concat(
    [for b in var.allowed_branches : "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${b}"],
    ["repo:${var.github_org}/${var.github_repo}:pull_request"],
  )
}

###############################################################################
# 3. Scoped IAM role assumed by the pipeline
###############################################################################
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subs
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = var.pipeline_role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  description        = "Assumed by GitHub Actions (OIDC) to deploy the AI cost module."
}

# Permissions: exactly what terraform-ai-cost touches + read/write its state.
data "aws_iam_policy_document" "permissions" {
  # Cost allocation tags + Cost Categories (Cost Explorer billing APIs).
  statement {
    sid    = "CostExplorerAllocationAndCategories"
    effect = "Allow"
    actions = [
      "ce:ListCostAllocationTags",
      "ce:UpdateCostAllocationTagsStatus",
      "ce:GetCostAndUsage",
      "ce:CreateCostCategoryDefinition",
      "ce:UpdateCostCategoryDefinition",
      "ce:DeleteCostCategoryDefinition",
      "ce:DescribeCostCategoryDefinition",
      "ce:ListCostCategoryDefinitions",
      "ce:ListTagsForResource",
      "ce:TagResource",
      "ce:UntagResource",
    ]
    resources = ["*"]
  }

  # AWS Budgets.
  statement {
    sid    = "Budgets"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ModifyBudget",
      "budgets:CreateBudget",
      "budgets:DeleteBudget",
      "budgets:DescribeBudget",
      "budgets:DescribeBudgetAction",
    ]
    resources = ["*"]
  }

  # Read own identity (Terraform aws_caller_identity + provider account guard).
  statement {
    sid       = "StsIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # Remote state access.
  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
  statement {
    sid       = "StateObjectRW"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "${var.pipeline_role_name}-permissions"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.permissions.json
}
