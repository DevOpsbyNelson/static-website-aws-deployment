# Resources moved from the root module into modules/static-website.
# Lets existing workspace states upgrade in place instead of destroying and recreating.
moved {
  from = aws_s3_bucket.site
  to   = module.website.aws_s3_bucket.site
}

moved {
  from = aws_s3_bucket_public_access_block.site
  to   = module.website.aws_s3_bucket_public_access_block.site
}

moved {
  from = aws_s3_bucket_ownership_controls.site
  to   = module.website.aws_s3_bucket_ownership_controls.site
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.site
  to   = module.website.aws_s3_bucket_server_side_encryption_configuration.site
}

moved {
  from = aws_s3_bucket_versioning.site
  to   = module.website.aws_s3_bucket_versioning.site
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.site
  to   = module.website.aws_s3_bucket_lifecycle_configuration.site
}

moved {
  from = aws_s3_bucket_policy.site
  to   = module.website.aws_s3_bucket_policy.site
}

moved {
  from = aws_cloudfront_origin_access_control.site
  to   = module.website.aws_cloudfront_origin_access_control.site
}

moved {
  from = aws_cloudfront_distribution.site
  to   = module.website.aws_cloudfront_distribution.site
}

moved {
  from = aws_s3_object.site
  to   = module.website.aws_s3_object.site
}

moved {
  from = terraform_data.invalidate_cache
  to   = module.website.terraform_data.invalidate_cache[0]
}
