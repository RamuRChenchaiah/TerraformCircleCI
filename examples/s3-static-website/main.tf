# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE A STATIC WEBSITE IN AN S3 BUCKET
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
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE STATIC WEBSITE
# ---------------------------------------------------------------------------------------------------------------------

module "static_website" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-static-assets.git//modules/s3-static-website?ref=v1.0.8"
  source = "../../modules/s3-static-website"

  website_domain_name       = var.website_domain_name
  index_document            = var.index_document
  error_document            = var.error_document
  add_random_id_name_suffix = var.add_random_id_name_suffix

  create_route53_entry = var.create_route53_entry
  hosted_zone_id       = var.hosted_zone_id

  # This is only set here so we can easily run automated tests on this code. You should NOT copy this setting into
  # your real applications.
  force_destroy_website            = var.force_destroy_website
  force_destroy_access_logs_bucket = var.force_destroy_access_logs_bucket

  # An example of how to enable lifecycle rules
  lifecycle_rules = {
    ExampleRule = {
      prefix  = "config/"
      enabled = true

      noncurrent_version_transition = {
        ToStandardIa = {
          days          = 30
          storage_class = "STANDARD_IA"
        }

        ToGlacier = {
          days          = 60
          storage_class = "GLACIER"
        }
      }

      noncurrent_version_expiration = 90
    }
  }

  # An example of using routing_rule.
  routing_rule = {
    condition = {
      http_error_code_returned_equals = "401"
    }

    redirect = {
      replace_key_with = "error.html"
    }
  }
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
# CREATE A BUCKET FOR REDIRECTS
# This bucket just redirects all requests to it to the static website bucket created above. This is useful when you
# are running a static website on www.foo.com and want to redirect all requests from foo.com to www.foo.com too.
# ---------------------------------------------------------------------------------------------------------------------

module "redirect" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-static-assets.git//modules/s3-static-website?ref=v1.0.8"
  source = "../../modules/s3-static-website"

  website_domain_name          = "redirect-${var.website_domain_name}"
  should_redirect_all_requests = true
  redirect_all_requests_to     = module.static_website.website_domain_name

  create_route53_entry = var.create_route53_entry
  hosted_zone_id       = var.hosted_zone_id

  # This is only set here so we can easily run automated tests on this code. You should NOT copy this setting into
  # your real applications.
  force_destroy_redirect           = var.force_destroy_redirect
  force_destroy_access_logs_bucket = var.force_destroy_access_logs_bucket
}
