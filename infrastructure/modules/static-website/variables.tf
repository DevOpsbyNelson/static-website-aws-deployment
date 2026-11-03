variable "name" {
  description = "Name prefix for the CloudFront resources (e.g. \"static-website-development\")."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique name of the S3 bucket that stores the site files."
  type        = string
}

variable "site_dir" {
  description = "Absolute path to the built website folder whose files are uploaded. Missing or empty folder uploads nothing."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class: PriceClass_100 (NA/EU), PriceClass_200 or PriceClass_All."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "force_destroy" {
  description = "Allow destroying the bucket even when it still contains files."
  type        = bool
  default     = false
}

variable "noncurrent_version_days" {
  description = "Days to keep previous versions of files (for rollback) before they expire."
  type        = number
  default     = 30
}

variable "spa_fallback" {
  description = "Serve index.html for unknown paths (403/404) so client-side routing works."
  type        = bool
  default     = true
}

variable "immutable_path_prefix" {
  description = "Key prefix of fingerprinted files that may be cached forever (Vite: \"assets/\")."
  type        = string
  default     = "assets/"
}

variable "invalidate_on_change" {
  description = "Invalidate the CloudFront cache when site files change. Requires the AWS CLI where Terraform runs."
  type        = bool
  default     = true
}
