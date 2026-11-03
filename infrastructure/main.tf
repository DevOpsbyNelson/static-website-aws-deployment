data "aws_caller_identity" "current" {}

module "website" {
  source = "./modules/static-website"

  name = local.name_prefix
  # Account ID suffix keeps the globally unique bucket name from colliding.
  bucket_name = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
  site_dir    = abspath("${path.root}/${var.site_dir}")

  price_class             = local.stage_settings.price_class
  force_destroy           = local.stage_settings.force_destroy
  noncurrent_version_days = local.stage_settings.noncurrent_version_days
}
