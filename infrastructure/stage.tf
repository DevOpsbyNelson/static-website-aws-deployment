locals {
  # The Terraform workspace is the deployment stage (development, staging, production).
  stage        = coalesce(var.stage, terraform.workspace)
  stage_config = lookup(var.stages, local.stage, null)
  name_prefix  = "${var.project_name}-${local.stage}"

  # Values passed to the module. The placeholder for an unknown stage only lets the plan reach
  # stage_guard's clear error message; it is never applied because that guard fails the plan.
  stage_settings = coalesce(local.stage_config, {
    price_class             = "PriceClass_100"
    force_destroy           = false
    noncurrent_version_days = 1
  })
}

# Fails plan/apply early when the selected workspace is not a configured stage (e.g. "default").
resource "terraform_data" "stage_guard" {
  lifecycle {
    precondition {
      condition     = local.stage_config != null
      error_message = "Workspace \"${terraform.workspace}\" is not a configured stage. Run `terraform workspace select <stage>` with one of: ${join(", ", keys(var.stages))}."
    }

    # var.stage must not point a stage's workspace at another stage's resources.
    precondition {
      condition     = var.stage == null || terraform.workspace == "default" || var.stage == terraform.workspace
      error_message = "var.stage (\"${coalesce(var.stage, "-")}\") does not match workspace \"${terraform.workspace}\". Leave var.stage unset outside of tests."
    }
  }
}
