output "website_url" {
  description = "Public URL of the website."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "bucket_name" {
  description = "S3 bucket holding the website files."
  value       = aws_s3_bucket.site.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for manual cache invalidations)."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name (target for a DNS CNAME/alias record)."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "uploaded_file_count" {
  description = "Number of files uploaded from site_dir."
  value       = length(aws_s3_object.site)
}
