# Unit tests for the static-website module. The AWS provider is mocked: no credentials needed,
# nothing is created. Run from modules/static-website: terraform init && terraform test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_cloudfront_cache_policy" {
    defaults = {
      id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    }
  }

  mock_data "aws_cloudfront_response_headers_policy" {
    defaults = {
      id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::123456789012:distribution/EMOCK"
      domain_name = "dmock.cloudfront.net"
    }
  }
}

variables {
  name        = "test-site"
  bucket_name = "test-site-bucket"
  site_dir    = "tests/fixtures/site"
}

run "secure_bucket_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.site.bucket == "test-site-bucket"
    error_message = "Bucket name must come from var.bucket_name."
  }

  assert {
    condition     = aws_s3_bucket.site.force_destroy == false
    error_message = "force_destroy must default to false."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.site.block_public_acls,
      aws_s3_bucket_public_access_block.site.block_public_policy,
      aws_s3_bucket_public_access_block.site.ignore_public_acls,
      aws_s3_bucket_public_access_block.site.restrict_public_buckets,
    ])
    error_message = "All public access must be blocked."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.site.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled (BucketOwnerEnforced)."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.site.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Bucket must be encrypted by default."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.site.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.site.rule).noncurrent_version_expiration).noncurrent_days == 30
    error_message = "Old versions must expire after the default 30 days."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.site.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after 7 days."
  }
}

run "cloudfront_defaults" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.site.price_class == "PriceClass_100"
    error_message = "price_class must default to PriceClass_100."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.default_root_object == "index.html"
    error_message = "Root path must serve index.html."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "HTTP must redirect to HTTPS."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.site.name == "test-site-oac" && aws_cloudfront_origin_access_control.site.signing_behavior == "always"
    error_message = "OAC must be named after var.name and always sign requests."
  }

  assert {
    condition     = toset([for r in aws_cloudfront_distribution.site.custom_error_response : r.error_code]) == toset([403, 404])
    error_message = "SPA fallback must handle 403 and 404."
  }

  assert {
    condition     = alltrue([for r in aws_cloudfront_distribution.site.custom_error_response : r.response_page_path == "/index.html" && r.response_code == 200])
    error_message = "SPA fallback must return /index.html with status 200."
  }
}

run "uploads_site_files" {
  command = plan

  assert {
    condition     = length(aws_s3_object.site) == 4
    error_message = "Every file in site_dir must be uploaded."
  }

  assert {
    condition     = aws_s3_object.site["index.html"].content_type == "text/html; charset=utf-8"
    error_message = "index.html must be served as HTML."
  }

  assert {
    condition     = aws_s3_object.site["assets/index-abc123.js"].content_type == "text/javascript; charset=utf-8"
    error_message = "JavaScript must be served as text/javascript."
  }

  assert {
    condition     = aws_s3_object.site["assets/index-abc123.css"].content_type == "text/css; charset=utf-8"
    error_message = "CSS must be served as text/css."
  }

  assert {
    condition     = aws_s3_object.site["favicon.svg"].content_type == "image/svg+xml"
    error_message = "SVG must be served as image/svg+xml."
  }

  assert {
    condition     = aws_s3_object.site["assets/index-abc123.js"].cache_control == "public, max-age=31536000, immutable"
    error_message = "Fingerprinted assets must be cached forever."
  }

  assert {
    condition     = aws_s3_object.site["index.html"].cache_control == "public, max-age=0, must-revalidate"
    error_message = "index.html must always be revalidated."
  }

  assert {
    condition     = length(terraform_data.invalidate_cache) == 1
    error_message = "Cache invalidation must be enabled by default."
  }
}

run "empty_site_dir_uploads_nothing" {
  command = plan

  variables {
    site_dir = "tests/fixtures/does-not-exist"
  }

  assert {
    condition     = length(aws_s3_object.site) == 0
    error_message = "A missing build folder must upload nothing."
  }
}

run "optional_features_can_be_disabled" {
  command = plan

  variables {
    spa_fallback         = false
    invalidate_on_change = false
  }

  assert {
    condition     = length(aws_cloudfront_distribution.site.custom_error_response) == 0
    error_message = "spa_fallback = false must remove the error responses."
  }

  assert {
    condition     = length(terraform_data.invalidate_cache) == 0
    error_message = "invalidate_on_change = false must skip the invalidation."
  }
}

run "rejects_invalid_price_class" {
  command = plan

  variables {
    price_class = "PriceClass_Cheap"
  }

  expect_failures = [var.price_class]
}

run "apply_outputs" {
  # Mocked apply; invalidation is off so the AWS CLI isn't called.
  variables {
    invalidate_on_change = false
  }

  assert {
    condition     = output.website_url == "https://dmock.cloudfront.net"
    error_message = "website_url must be the HTTPS CloudFront URL."
  }

  assert {
    condition     = output.bucket_name == "test-site-bucket"
    error_message = "bucket_name output must match the bucket."
  }

  assert {
    condition     = output.uploaded_file_count == 4
    error_message = "uploaded_file_count must count the uploaded files."
  }
}
