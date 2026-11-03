variable "aws_region" {
  description = "AWS region for the S3 bucket."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used for the bucket and resource names. Lowercase letters, numbers and hyphens only."
  type        = string
  default     = "static-website"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 chars of lowercase letters, numbers and hyphens."
  }
}

variable "s3_use_path_style" {
  description = "Use path-style S3 URLs. Set to true when AWS_ENDPOINT_URL points at a local emulator."
  type        = bool
  default     = false
}

variable "site_dir" {
  description = "Path to the built website (Vite output), relative to this folder."
  type        = string
  default     = "../website/dist"
}

variable "force_destroy_override" {
  description = "Let the stage's bucket be deleted with its files, overriding stages[*].force_destroy. Set only to tear a stage down (scripts/deploy.sh with ACTION=destroy does it)."
  type        = bool
  default     = false
}

variable "stage" {
  description = "Stage to use instead of the workspace name. Meant for `terraform test`, which always runs in the default workspace; leave unset otherwise."
  type        = string
  default     = null
}

# Per-stage settings. The active stage is selected by the Terraform workspace name:
#   terraform workspace select development|staging|production
variable "stages" {
  description = "Settings for each deployment stage, keyed by Terraform workspace name."
  type = map(object({
    price_class             = string # PriceClass_100 (NA/EU), PriceClass_200 or PriceClass_All
    force_destroy           = bool   # allow `terraform destroy` to delete a non-empty bucket
    noncurrent_version_days = number # how long old file versions are kept for rollback
  }))

  default = {
    development = {
      price_class             = "PriceClass_100"
      force_destroy           = true
      noncurrent_version_days = 7
    }
    staging = {
      price_class             = "PriceClass_100"
      force_destroy           = true
      noncurrent_version_days = 14
    }
    production = {
      price_class             = "PriceClass_All"
      force_destroy           = false
      noncurrent_version_days = 90
    }
  }
}
