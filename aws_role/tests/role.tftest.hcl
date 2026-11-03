# Unit tests for the GitHub Actions OIDC deploy role. The AWS provider is mocked: no credentials
# needed, nothing is created. Run from aws_role/: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/existing"
    }
  }
}

variables {
  github_repository  = "acme/site"
  state_bucket_names = ["acme-tfstate"]
}

run "trust_policy_is_limited_to_repo_environments" {
  assert {
    condition = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:acme/site:environment:development",
      "repo:acme/site:environment:staging",
      "repo:acme/site:environment:production",
    ]
    error_message = "Only the repo's development/staging/production environments may assume the role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The token audience must be sts.amazonaws.com."
  }

  assert {
    condition     = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "The role must be assumed with a web identity token."
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1 && jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Principal.Federated == aws_iam_openid_connect_provider.github[0].arn
    error_message = "By default the OIDC provider is created and trusted."
  }

  assert {
    condition     = aws_iam_role.deploy.name == "github-actions-static-website-deploy" && aws_iam_role.deploy.max_session_duration == 3600
    error_message = "Role name and session length must use the defaults."
  }
}

run "reuses_existing_oidc_provider" {
  variables {
    create_oidc_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "No provider may be created when create_oidc_provider = false."
  }

  assert {
    condition     = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/existing"
    error_message = "The existing provider must be trusted."
  }
}

run "deploy_policy_is_scoped" {
  assert {
    condition = one([for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "WebsiteBuckets"]) == [
      "arn:aws:s3:::static-website-development-123456789012",
      "arn:aws:s3:::static-website-staging-123456789012",
      "arn:aws:s3:::static-website-production-123456789012",
      "arn:aws:s3:::static-website-development-123456789012/*",
      "arn:aws:s3:::static-website-staging-123456789012/*",
      "arn:aws:s3:::static-website-production-123456789012/*",
    ]
    error_message = "s3:* must be limited to the per-stage website buckets."
  }

  assert {
    condition = one([for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : s.Resource if s.Sid == "TerraformStateObjects"]) == [
      "arn:aws:s3:::acme-tfstate/env:/*",
      "arn:aws:s3:::acme-tfstate/static-website/terraform.tfstate",
      "arn:aws:s3:::acme-tfstate/static-website/terraform.tfstate.tflock",
    ]
    error_message = "State access must be limited to the infrastructure/ state keys."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement :
      !(contains(s.Action, "s3:*") && anytrue([for r in flatten([s.Resource]) : startswith(r, "arn:aws:s3:::acme-tfstate")]))
    ])
    error_message = "The state bucket must never get s3:*."
  }

  assert {
    condition     = !anytrue([for s in jsondecode(aws_iam_role_policy.deploy.policy).Statement : anytrue([for a in s.Action : startswith(a, "iam:")])])
    error_message = "The deploy role must not get any IAM permissions."
  }
}

run "custom_environments" {
  variables {
    github_environments = ["prod"]
  }

  assert {
    condition     = output.allowed_subjects == ["repo:acme/site:environment:prod"]
    error_message = "allowed_subjects must follow github_environments."
  }
}

run "immutable_subject_uses_numeric_ids" {
  variables {
    github_repository_owner_id = 111
    github_repository_id       = 222
  }

  assert {
    condition = output.allowed_subjects == [
      "repo:acme@111/site@222:environment:development",
      "repo:acme@111/site@222:environment:staging",
      "repo:acme@111/site@222:environment:production",
    ]
    error_message = "Immutable subjects must include the owner and repository IDs."
  }
}

run "rejects_only_one_repository_id" {
  command = plan

  variables {
    github_repository_id = 222
  }

  expect_failures = [var.github_repository_id]
}

run "rejects_invalid_repository" {
  command = plan

  variables {
    github_repository = "not-a-repo"
  }

  expect_failures = [var.github_repository]
}

run "rejects_empty_environments" {
  command = plan

  variables {
    github_environments = []
  }

  expect_failures = [var.github_environments]
}

run "rejects_missing_state_buckets" {
  command = plan

  variables {
    state_bucket_names = []
  }

  expect_failures = [var.state_bucket_names]
}
