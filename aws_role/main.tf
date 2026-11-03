data "aws_caller_identity" "current" {}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  account_id       = data.aws_caller_identity.current.account_id

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # GitHub puts "repo:<owner>/<repo>:environment:<name>" in the token's sub claim for jobs
  # that use `environment:`, so only those deploy jobs can assume the role.
  allowed_subjects = [for env in var.github_environments : "repo:${var.github_repository}:environment:${env}"]

  website_bucket_arns = [for env in var.github_environments : "arn:aws:s3:::${var.project_name}-${env}-${local.account_id}"]
  state_bucket_arns   = [for b in var.state_bucket_names : "arn:aws:s3:::${b}"]
}

# One GitHub OIDC provider per AWS account. With create_oidc_provider = false the existing one is used.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://${local.github_oidc_host}"
}

resource "aws_iam_role" "deploy" {
  name                 = var.role_name
  description          = "Assumed by GitHub Actions (${var.github_repository}) via OIDC to deploy ${var.project_name}."
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsOIDC"
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub" = local.allowed_subjects
        }
      }
    }]
  })
}

# Least privilege for infrastructure/: its Terraform state, the website buckets and CloudFront.
resource "aws_iam_role_policy" "deploy" {
  name = "${var.project_name}-deploy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TerraformStateList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.state_bucket_arns
      },
      {
        # State files, workspace states under env:/ and the .tflock lock files.
        Sid      = "TerraformStateObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [for arn in local.state_bucket_arns : "${arn}/*"]
      },
      {
        # Only the per-stage website buckets (<project>-<stage>-<account>), never the state buckets.
        Sid      = "WebsiteBuckets"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = concat(local.website_bucket_arns, [for arn in local.website_bucket_arns : "${arn}/*"])
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:ListTagsForResource",
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:GetOriginAccessControlConfig",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:ListOriginAccessControls",
          "cloudfront:GetCachePolicy",
          "cloudfront:ListCachePolicies",
          "cloudfront:GetResponseHeadersPolicy",
          "cloudfront:ListResponseHeadersPolicies",
        ]
        Resource = "*"
      },
    ]
  })
}
