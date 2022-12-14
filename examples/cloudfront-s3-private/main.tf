# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE A STATIC WEBSITE IN AN S3 BUCKET AND DEPLOY CLOUDFRONT AS A CDN IN FRONT OF IT
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"
}
# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  # The AWS region in which all resources will be created
  region = var.aws_region

  # Only these AWS Account IDs may be operated on by this template
  allowed_account_ids = [var.aws_account_id]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE STATIC WEBSITE
# ---------------------------------------------------------------------------------------------------------------------

module "static_website" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-static-assets.git//modules/s3-static-website?ref=v1.0.8"
  source = "../../modules/s3-static-website"

  website_domain_name = var.website_domain_name
  index_document      = var.index_document
  error_document      = var.error_document

  # Don't allow access to the S3 bucket directly. Only allow CloudFront to access it.
  restrict_access_to_cloudfront                          = true
  cloudfront_origin_access_identity_iam_arn              = var.use_canonical_iam_user_for_s3 ? null : module.cloudfront.cloudfront_origin_access_identity_iam_arn
  cloudfront_origin_access_identity_s3_canonical_user_id = var.use_canonical_iam_user_for_s3 ? module.cloudfront.cloudfront_origin_access_identity_s3_canonical_user_id : null

  # This is only set here so we can easily run automated tests on this code. You should NOT copy this setting into
  # your real applications.
  force_destroy_access_logs_bucket = var.force_destroy_access_logs_bucket
  force_destroy_redirect           = var.force_destroy_redirect
  force_destroy_website            = var.force_destroy_website
}

# ---------------------------------------------------------------------------------------------------------------------
# UPLOAD THE EXAMPLE WEBSITE INTO THE S3 BUCKET
# Normally, you would have some sort of CI process upload your static website, but to keep this example simple, we are
# using Terraform to do it.
# ---------------------------------------------------------------------------------------------------------------------
resource "null_resource" "upload" {
  provisioner "local-exec" {
    command = "../bin/s3-upload.sh ${module.static_website.website_bucket_name}"
  }
}
# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE CLOUDFRONT WEB DISTRIBUTION
# ---------------------------------------------------------------------------------------------------------------------

module "cloudfront" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-static-assets.git//modules/s3-cloudfront?ref=v1.0.8"
  source = "../../modules/s3-cloudfront"

  bucket_name                 = var.website_domain_name
  s3_bucket_is_public_website = false

  # Make sure the CloudFront distribution depends on the S3 Bucket being fully configured
  enabled = module.static_website.website_bucket_is_fully_configured

  index_document = "index.html"

  error_responses = {
    404 = {
      response_code         = 404
      response_page_path    = "error.html"
      error_caching_min_ttl = 0
    },
    500 = {
      response_code         = 500
      response_page_path    = "error.html"
      error_caching_min_ttl = 0
    }
  }

  min_ttl     = 0
  max_ttl     = 60
  default_ttl = 30

  ordered_cache_behaviors = [
    {
      path_pattern           = "/.well-known/apple-app-site-association*"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      viewer_protocol_policy = "redirect-to-https"
      compress               = true
      forwarded_values = [{
        cookies_forward = "none"
        query_string    = true
      }]
    },
  ]

  create_route53_entries = var.create_route53_entry
  domain_names           = var.create_route53_entry ? [var.website_domain_name] : []
  hosted_zone_id         = var.hosted_zone_id

  # If var.create_route53_entry is false, the aws_acm_certificate data source won't be created. Ideally, we'd just use
  # a conditional to only use that data source if var.create_route53_entry is true, but Terraform's conditionals are
  # not short-circuiting, so both branches would be evaluated. Therefore, we use this silly trick with "join" to get
  # back an empty string if the data source was not created.
  acm_certificate_arn = join(",", data.aws_acm_certificate.cert.*.arn)

  use_cloudfront_default_certificate = var.create_route53_entry ? false : true

  # This is only set here so we can easily run automated tests on this code. You should NOT copy this setting into
  # your real applications.
  force_destroy_access_logs_bucket = var.force_destroy_access_logs_bucket

  use_cloudfront_arn_for_bucket_policy = var.use_cloudfront_arn_for_bucket_policy
}

# ---------------------------------------------------------------------------------------------------------------------
# FIND THE ACM CERTIFICATE
# If var.create_route53_entry is true, we need a custom TLS cert for our custom domain name. Here, we look for a
# cert issued by Amazon's Certificate Manager (ACM) for the domain name var.acm_certificate_domain_name.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_acm_certificate" "cert" {
  count    = var.create_route53_entry ? 1 : 0
  domain   = var.acm_certificate_domain_name
  statuses = ["ISSUED"]
}
