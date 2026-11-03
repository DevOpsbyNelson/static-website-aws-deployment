# Tests for the per-stage (workspace) wiring of the root configuration. The AWS provider is mocked.
# `terraform test` always runs in the default workspace, so runs select a stage through var.stage.
# Run from infrastructure/: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  site_dir = "modules/static-website/tests/fixtures/site"
}

run "default_workspace_is_rejected" {
  command = plan

  expect_failures = [terraform_data.stage_guard]
}

run "unknown_stage_is_rejected" {
  command = plan

  variables {
    stage = "qa"
  }

  expect_failures = [terraform_data.stage_guard]
}

run "development" {
  command = plan

  variables {
    stage = "development"
  }

  assert {
    condition     = module.website.bucket_name == "static-website-development-123456789012"
    error_message = "Bucket name must include project, stage and account ID."
  }

  assert {
    condition     = local.stage_config.price_class == "PriceClass_100" && local.stage_config.force_destroy && local.stage_config.noncurrent_version_days == 7
    error_message = "development must use cheap, disposable settings."
  }

  assert {
    condition     = output.stage == "development" && output.uploaded_file_count == 4
    error_message = "Outputs must report the stage and uploaded files."
  }
}

run "staging" {
  command = plan

  variables {
    stage = "staging"
  }

  assert {
    condition     = module.website.bucket_name == "static-website-staging-123456789012"
    error_message = "Bucket name must include project, stage and account ID."
  }

  assert {
    condition     = local.stage_config.noncurrent_version_days == 14
    error_message = "staging must keep old versions for 14 days."
  }
}

run "production" {
  command = plan

  variables {
    stage = "production"
  }

  assert {
    condition     = module.website.bucket_name == "static-website-production-123456789012"
    error_message = "Bucket name must include project, stage and account ID."
  }

  assert {
    condition     = local.stage_config.price_class == "PriceClass_All"
    error_message = "production must serve from all edge locations."
  }

  assert {
    condition     = local.stage_config.force_destroy == false
    error_message = "production bucket must be protected from destroy."
  }

  assert {
    condition     = local.stage_config.noncurrent_version_days == 90
    error_message = "production must keep old versions for 90 days."
  }
}

run "force_destroy_override_unlocks_production" {
  command = plan

  variables {
    stage                  = "production"
    force_destroy_override = true
  }

  assert {
    condition     = module.website.bucket_force_destroy == true
    error_message = "force_destroy_override must let the production bucket be deleted."
  }

  assert {
    condition     = local.stage_config.force_destroy == false
    error_message = "The override must not change the stage's own setting."
  }
}

run "production_bucket_is_protected_by_default" {
  command = plan

  variables {
    stage = "production"
  }

  assert {
    condition     = module.website.bucket_force_destroy == false
    error_message = "Without the override the production bucket must stay protected."
  }
}

run "project_name_is_validated" {
  command = plan

  variables {
    stage        = "development"
    project_name = "Invalid_Name"
  }

  expect_failures = [var.project_name]
}
