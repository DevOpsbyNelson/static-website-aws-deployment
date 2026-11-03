output "stage" {
  description = "Deployment stage (Terraform workspace) these outputs belong to."
  value       = local.stage
}

output "website_url" {
  description = "Public URL of the website."
  value       = module.website.website_url
}

output "bucket_name" {
  description = "S3 bucket holding the website files."
  value       = module.website.bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for manual cache invalidations)."
  value       = module.website.cloudfront_distribution_id
}

output "uploaded_file_count" {
  description = "Number of files uploaded from the build folder."
  value       = module.website.uploaded_file_count
}
