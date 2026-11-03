locals {
  site_files = fileset(var.site_dir, "**")

  mime_types = {
    html        = "text/html; charset=utf-8"
    css         = "text/css; charset=utf-8"
    js          = "text/javascript; charset=utf-8"
    mjs         = "text/javascript; charset=utf-8"
    json        = "application/json"
    map         = "application/json"
    svg         = "image/svg+xml"
    png         = "image/png"
    jpg         = "image/jpeg"
    jpeg        = "image/jpeg"
    gif         = "image/gif"
    webp        = "image/webp"
    avif        = "image/avif"
    ico         = "image/x-icon"
    txt         = "text/plain; charset=utf-8"
    xml         = "application/xml"
    webmanifest = "application/manifest+json"
    woff        = "font/woff"
    woff2       = "font/woff2"
    ttf         = "font/ttf"
  }

  # Hash of every file, used to trigger a CloudFront invalidation only when content changes.
  site_hash = sha1(join(",", [for f in sort(local.site_files) : "${f}:${filemd5("${var.site_dir}/${f}")}"]))
}

resource "aws_s3_object" "site" {
  for_each = local.site_files

  bucket       = aws_s3_bucket.site.id
  key          = each.value
  source       = "${var.site_dir}/${each.value}"
  source_hash  = filemd5("${var.site_dir}/${each.value}")
  content_type = lookup(local.mime_types, lower(element(split(".", each.value), length(split(".", each.value)) - 1)), "application/octet-stream")

  # Fingerprinted files (e.g. assets/index-z1dqokgX.js) can be cached forever.
  # Everything else (index.html, favicon, ...) must be revalidated so new deploys show up.
  cache_control = startswith(each.value, var.immutable_path_prefix) ? "public, max-age=31536000, immutable" : "public, max-age=0, must-revalidate"
}

# Clear CloudFront's cache after content changes. Requires the AWS CLI.
resource "terraform_data" "invalidate_cache" {
  count = var.invalidate_on_change ? 1 : 0

  triggers_replace = [local.site_hash]

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.site.id} --paths '/*' --output text --query Invalidation.Id"
  }

  depends_on = [aws_s3_object.site]
}
