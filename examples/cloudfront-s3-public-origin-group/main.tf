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

  # This is only set here so we can easily run automated tests on this code. You should NOT copy this setting into
  # your real applications.
  force_destroy_access_logs_bucket = var.force_destroy_access_logs_bucket
  force_destroy_redirect           = var.force_destroy_redirect
  force_destroy_website            = var.force_destroy_website
}

module "failover_static_website" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-static-assets.git//modules/s3-static-website?ref=v1.0.8"
  source = "../../modules/s3-static-website"

  website_domain_name = var.failover_website_domain_names[0]
  index_document      = var.index_document
  error_document      = var.error_document

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

resource "null_resource" "upload_failover" {
  provisioner "local-exec" {
    command = "../bin/s3-upload.sh ${module.failover_static_website.website_bucket_name}"
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

  bucket_name                       = var.website_domain_name
  failover_buckets                  = var.failover_website_domain_names
  s3_bucket_is_public_website       = true
  bucket_website_endpoint           = module.static_website.website_bucket_endpoint
  failover_bucket_website_endpoints = [module.failover_static_website.website_bucket_endpoint]

  # Make sure the CloudFront distribution depends on the S3 Bucket being fully configured
  enabled = module.static_website.website_bucket_is_fully_configured

  index_document = var.index_document

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

  create_route53_entries = var.create_route53_entries
  domain_names           = [var.website_domain_name]
  hosted_zone_id         = var.hosted_zone_id

  # If var.create_route53_entries is false, the aws_acm_certificate data source won't be created. Ideally, we'd just usieies
  # a conditional to only use that data source if var.create_route53_entries is true, but Terraform's conditionals are
  # not short-circuiting, so both branches would be evaluated. Therefore, we use this silly trick with "join" to get
  # back an empty string if the data source was not created.
  acm_certificate_arn = join(",", data.aws_acm_certificate.cert.*.arn)

  use_cloudfront_default_certificate = false

  # This is only set here so we can easily run automated tests on this code. You should NOT copy this setting into
  # your real applications.
  force_destroy_access_logs_bucket = var.force_destroy_access_logs_bucket

  use_cloudfront_arn_for_bucket_policy = var.use_cloudfront_arn_for_bucket_policy
}

# ---------------------------------------------------------------------------------------------------------------------
# FIND THE ACM CERTIFICATE
# If var.create_route53_entries is true, we need a custom TLS cert for our custom domain name. Here, we look for a
# cert issued by Amazon's Certificate Manager (ACM) for the domain name var.acm_certificate_domain_name.
# ---------------------------------------------------------------------------------------------------------------------

# Note that ACM certs for CloudFront MUST be in us-east-1!
provider "aws" {
  alias  = "east"
  region = "us-east-1"
}

data "aws_acm_certificate" "cert" {
  count    = var.create_route53_entries ? 1 : 0
  provider = aws.east

  domain   = var.acm_certificate_domain_name
  statuses = ["ISSUED"]
}