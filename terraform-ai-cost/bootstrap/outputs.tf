output "state_bucket" {
  description = "S3 bucket for the AI-cost module remote state. Use in the backend block."
  value       = aws_s3_bucket.tfstate.id
}

output "pipeline_role_arn" {
  description = "IAM role ARN the GitHub Actions workflow assumes. Set as repo variable AWS_ROLE_ARN."
  value       = aws_iam_role.pipeline.arn
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}

output "region" {
  value = "us-east-1"
}
