# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE A STATIC WEBSITE IN AN S3 BUCKET AND DEPLOY CLOUDFRONT AS A CDN IN FRONT OF IT WITH LAMBDA@EDGE FUNCTION
# SUPPORT
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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

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
  s3_bucket_is_public_website = true
  disable_logging             = true
  bucket_website_endpoint     = module.static_website.website_bucket_endpoint

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

  # This is only set here so we can easily run automated tests on this code. You should NOT copy this setting into
  # your real applications.
  force_destroy_access_logs_bucket = var.force_destroy_access_logs_bucket

  use_cloudfront_arn_for_bucket_policy = var.use_cloudfront_arn_for_bucket_policy

  # Link the Lambda@Edge function so that it updates the origin response.
  default_lambda_associations = [
    {
      event_type   = "origin-response"
      include_body = false
      # We use a tautology here to link this module to the time_sleep so that the distribution gets deleted before the
      # time_sleep on destroy. We do this instead of using a module depends_on, because module depends_on can lead to a
      # perpetual diff of data sources used within the module.
      lambda_arn = (
        time_sleep.wait_20_mins.id == null
        ? module.lambda_edge.qualified_arn
        : module.lambda_edge.qualified_arn
      )
    }
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE LAMBDA FUNCTION TO MODIFY RESPONSE HEADERS
# ---------------------------------------------------------------------------------------------------------------------

module "lambda_edge" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-lambda.git//modules/lambda-edge?ref=v0.13.3"
  providers = {
    # Lambda@Edge function must be deployed in us-east-1
    aws = aws.us_east_1
  }

  name        = "${var.lambda_name_prefix}cloudfront-update-response"
  description = "An example of how to connect Lambda@Edge with CloudFront"

  source_path = "${path.module}/lambda"
  runtime     = "python3.7"
  handler     = "index.handler"

  timeout     = 30
  memory_size = 128
  tags = {
    Name = "${var.website_domain_name}-update-response"
  }
}

# We add a sleep here before destroying the lambda_edge module because it takes a long time for the lambda@edge replica
# to be removed from CloudFront, and we can't delete the lambda function until the replicas are removed from CloudFront.
# Refer to https://github.com/hashicorp/terraform-provider-aws/issues/1721 for more info.
resource "time_sleep" "wait_20_mins" {
  depends_on       = [module.lambda_edge]
  destroy_duration = "1200s"
}

# ---------------------------------------------------------------------------------------------------------------------
# FIND THE ACM CERTIFICATE
# If var.create_route53_entry is true, we need a custom TLS cert for our custom domain name. Here, we look for a
# cert issued by Amazon's Certificate Manager (ACM) for the domain name var.acm_certificate_domain_name.
# ---------------------------------------------------------------------------------------------------------------------

# Note that ACM certs for CloudFront MUST be in us-east-1!
provider "aws" {
  alias  = "east"
  region = "us-east-1"
}

data "aws_acm_certificate" "cert" {
  count    = var.create_route53_entry ? 1 : 0
  provider = aws.east

  domain   = var.acm_certificate_domain_name
  statuses = ["ISSUED"]
}
