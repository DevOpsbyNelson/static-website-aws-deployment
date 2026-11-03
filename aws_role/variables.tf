variable "aws_region" {
  description = "AWS region for the provider (IAM itself is global)."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the role, as \"owner/repo\"."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like \"owner/repo\"."
  }
}

variable "github_environments" {
  description = "GitHub environments (= deployment stages) whose jobs may assume the role."
  type        = list(string)
  default     = ["development", "staging", "production"]

  validation {
    condition     = length(var.github_environments) > 0 && alltrue([for e in var.github_environments : can(regex("^[a-z0-9-]+$", e))])
    error_message = "github_environments must be a non-empty list of lowercase names (letters, numbers, hyphens)."
  }
}

variable "project_name" {
  description = "project_name used by the infrastructure/ stack; website buckets are named <project_name>-<stage>-<account_id>."
  type        = string
  default     = "static-website"
}

variable "role_name" {
  description = "Name of the IAM role that GitHub Actions assumes."
  type        = string
  default     = "github-actions-static-website-deploy"
}

variable "state_bucket_names" {
  description = "S3 buckets holding the infrastructure/ Terraform state that the role may read and write."
  type        = list(string)

  validation {
    condition     = length(var.state_bucket_names) > 0
    error_message = "state_bucket_names must contain at least one bucket."
  }
}

variable "deploy_state_key" {
  description = "State key used by infrastructure/ (REMOTE_STORAGE_AWS_S3_KEY). The role may only touch this key and the env:/ workspace states."
  type        = string
  default     = "static-website/terraform.tfstate"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false when the AWS account already has one (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session length in seconds for the assumed role (3600-43200)."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}
