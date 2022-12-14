# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE A CLOUDFRONT WEB DISTRIBUTION IN FRONT OF AN S3 BUCKET
# Create a CloudFront web distribution that uses an S3 bucket as an origin server
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # This module is compatible with AWS provider ~> 4.13.0, but to make upgrading easier we are setting 3.75.1 as the minimum version.
      version = ">= 3.75.1"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# PREPARE LOCALS
#
# NOTE: Since v2.x AWS provider release, we have to construct some of the configuration values dynamically
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Determine the certificate type
  is_iam_cert = var.iam_certificate_id != ""
  is_acm_cert = var.acm_certificate_arn != ""

  # We will use this value if we are configuration a CloudFront distribution with an Origin Group.
  origin_group_id = "${var.bucket_name}-OriginGroup"

  # We will use these for our dynamic content generation
  all_buckets          = concat([var.bucket_name], var.failover_buckets)
  all_bucket_endpoints = concat([var.bucket_website_endpoint], var.failover_bucket_website_endpoints)
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE CLOUDFRONT DISTRIBUTION FOR A PRIVATE S3 BUCKET
# If var.s3_bucket_is_public_website is false, we create this resource, which is a CloudFront distribution that can
# access a private S3 bucket, authenticating itself via Origin Access Identity. This is a more secure option, but does
# not allow you to use website features in your S3 bucket, such as routing and custom error pages.
#
# In addition, you can leverage origin groups for this configuration by providing a bucket name for
# var.failover_bucket_name
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "private_s3_bucket" {
  count = var.s3_bucket_is_public_website ? 0 : 1

  aliases = var.domain_names
  enabled = var.enabled
  comment = "Serve S3 bucket ${var.bucket_name} via CloudFront."

  default_root_object = var.index_document
  web_acl_id          = var.web_acl_id

  is_ipv6_enabled = var.is_ipv6_enabled
  http_version    = var.http_version
  price_class     = var.price_class
  tags            = var.custom_tags

  # If set to true, the resource will wait for the distribution status to change from InProgress to Deployed
  wait_for_deployment = var.wait_for_deployment

  # Origin Groups require at least 2 Origins. we dynamically generate Origins depending on how many failover buckets are provided.
  #
  # You can provide a list of HTTP status codes for failover criteria. We will default to using
  # all 4xx and 5xx status codes CloudFront provides.
  #
  # For more info, see:
  #
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html

  dynamic "origin_group" {
    for_each = length(var.failover_buckets) > 0 ? [1] : []
    iterator = failover_bucket

    content {
      origin_id = local.origin_group_id

      failover_criteria {
        status_codes = var.failover_status_codes
      }

      # Primary bucket member
      member {
        origin_id = var.bucket_name
      }

      # All Failover bucket members
      dynamic "member" {
        for_each = var.failover_buckets
        iterator = bucket

        content {
          origin_id = bucket.value
        }
      }
    }
  }

  # If you set the origin domain_name to <BUCKET_NAME>.s3.amazonaws.com (the REST URL), CloudFront recognizes it as
  # an S3 bucket and a) it will talk to S3 over HTTPS and b) you can keep the bucket private and only allow it to be
  # accessed via CloudFront by using Origin Access Identity.
  #
  # The downside is that the S3 website features, such as routing and error pages, will NOT work with such a URL.
  # Moreover, this ONLY seems to work correctly if the bucket is in us-east-1.
  #
  # For more info, see:
  #
  # http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistS3AndCustomOrigins.html
  # http://stackoverflow.com/a/22750923/483528
  #
  dynamic "origin" {
    for_each = local.all_buckets
    iterator = bucket

    content {
      domain_name = try(var.additional_bucket_information[bucket.value].v4_auth, false) ? format("%s.s3.%s.amazonaws.com", bucket.value, var.additional_bucket_information[bucket.value].region) : format("%s.s3.amazonaws.com", bucket.value)

      origin_id   = bucket.value
      origin_path = var.s3_bucket_base_path

      s3_origin_config {
        origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
      }
    }
  }


  dynamic "logging_config" {
    for_each = length(module.access_logs) > 0 ? ["log"] : []

    content {
      include_cookies = var.include_cookies_in_logs
      bucket          = "${module.access_logs[0].name}.s3.amazonaws.com"
      prefix          = var.access_log_prefix
    }
  }

  # Caching behavior
  default_cache_behavior {
    allowed_methods            = length(var.failover_buckets) > 0 ? var.allowed_origin_group_methods : var.allowed_methods
    cached_methods             = var.cached_methods
    compress                   = var.compress
    trusted_signers            = var.trusted_signers
    trusted_key_groups         = length(var.trusted_signers) > 0 ? [] : var.trusted_key_groups
    response_headers_policy_id = var.response_headers_policy_id

    default_ttl = var.default_ttl
    min_ttl     = var.min_ttl
    max_ttl     = var.max_ttl

    target_origin_id       = length(var.failover_buckets) > 0 ? local.origin_group_id : var.bucket_name
    viewer_protocol_policy = var.viewer_protocol_policy

    forwarded_values {
      query_string = var.forward_query_string
      headers      = var.forward_headers

      cookies {
        forward           = var.forward_cookies
        whitelisted_names = var.whitelisted_cookie_names
      }
    }

    dynamic "lambda_function_association" {
      for_each = var.default_lambda_associations

      content {
        event_type   = lambda_function_association.value.event_type
        include_body = lambda_function_association.value.include_body
        lambda_arn   = lambda_function_association.value.lambda_arn
      }
    }

    dynamic "function_association" {
      for_each = var.default_function_associations

      content {
        event_type   = function_association.value.event_type
        function_arn = function_association.value.function_arn
      }
    }
  }

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#cache-behavior-arguments
  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors
    content {
      # Required parameters
      allowed_methods        = ordered_cache_behavior.value.allowed_methods
      cached_methods         = ordered_cache_behavior.value.cached_methods
      path_pattern           = ordered_cache_behavior.value.path_pattern
      viewer_protocol_policy = ordered_cache_behavior.value.viewer_protocol_policy
      target_origin_id       = length(var.failover_buckets) > 0 ? local.origin_group_id : var.bucket_name

      # Optional parameters
      cache_policy_id            = lookup(ordered_cache_behavior.value, "cache_policy_id", null)
      compress                   = lookup(ordered_cache_behavior.value, "compress", null)
      default_ttl                = lookup(ordered_cache_behavior.value, "default_ttl", null)
      field_level_encryption_id  = lookup(ordered_cache_behavior.value, "field_level_encryption_id", null)
      max_ttl                    = lookup(ordered_cache_behavior.value, "max_ttl", null)
      min_ttl                    = lookup(ordered_cache_behavior.value, "min_ttl", null)
      origin_request_policy_id   = lookup(ordered_cache_behavior.value, "origin_request_policy_id", null)
      realtime_log_config_arn    = lookup(ordered_cache_behavior.value, "realtime_log_config_arn", null)
      response_headers_policy_id = lookup(ordered_cache_behavior.value, "response_headers_policy_id", null)
      smooth_streaming           = lookup(ordered_cache_behavior.value, "smooth_streaming", null)
      trusted_key_groups         = lookup(ordered_cache_behavior.value, "trusted_key_groups", null)
      trusted_signers            = lookup(ordered_cache_behavior.value, "trusted_signers", null)

      # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#forwarded-values-arguments
      dynamic "forwarded_values" {
        for_each = lookup(ordered_cache_behavior.value, "forwarded_values", [])
        content {
          headers                 = lookup(forwarded_values.value, "headers", null)
          query_string            = forwarded_values.value.query_string
          query_string_cache_keys = lookup(forwarded_values.value, "query_string_cache_keys", null)
          cookies {
            forward           = forwarded_values.value.cookies_forward
            whitelisted_names = lookup(forwarded_values.value, "cookies_whitelisted_names", null)
          }
        }
      }

      # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#lambda-function-association
      dynamic "lambda_function_association" {
        for_each = lookup(ordered_cache_behavior.value, "lambda_function_association", [])
        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.lambda_arn
          include_body = lookup(lambda_function_association.value, "include_body", null)
        }
      }

      # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#function-association
      dynamic "function_association" {
        for_each = lookup(ordered_cache_behavior.value, "function_association", [])
        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.function_arn
        }
      }
    }
  } # end dynamic "ordered_cache_behavior"

  dynamic "custom_error_response" {
    for_each = var.error_responses != null ? var.error_responses : {}

    content {
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
      error_code            = custom_error_response.key
      response_code         = custom_error_response.value.response_code
      response_page_path    = "/${custom_error_response.value.response_page_path}"
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_locations_list
    }
  }

  viewer_certificate {
    minimum_protocol_version = var.minimum_protocol_version
    ssl_support_method       = local.is_acm_cert || local.is_iam_cert ? var.ssl_support_method : null
    acm_certificate_arn      = local.is_acm_cert ? var.acm_certificate_arn : null
    iam_certificate_id       = local.is_iam_cert ? var.iam_certificate_id : null

    # When an IAM or ACM cert is used, we won't use the default cert because a custom cert is provided. While setting
    # this to true has no effect, it causes a perpetual diff in the resource because the state returns as `false`.
    # See https://github.com/gruntwork-io/terraform-aws-static-assets/pull/26 for more context.
    cloudfront_default_certificate = local.is_acm_cert || local.is_iam_cert ? false : var.use_cloudfront_default_certificate
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE CLOUDFRONT DISTRIBUTION FOR A PUBLIC S3 BUCKET
# If var.s3_bucket_is_public_website is true, we create this resource, which is a CloudFront distribution that can
# access a public S3 bucket confired as a website. This requires that the S3 bucket is completely accessible to the
# public, so it's technically possible to bypass CloudFront. The advantage is that you can use all the S3 website
# features in your bucket, such as routing rules and custom error pages.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "public_website_s3_bucket" {
  count = var.s3_bucket_is_public_website ? 1 : 0

  aliases = var.domain_names
  enabled = var.enabled
  comment = "Serve S3 bucket ${var.bucket_name} via CloudFront."

  default_root_object = var.index_document
  web_acl_id          = var.web_acl_id

  is_ipv6_enabled = var.is_ipv6_enabled
  http_version    = var.http_version
  price_class     = var.price_class
  tags            = var.custom_tags

  # Origin Groups require at least 2 Origins. we dynamically generate Origins depending on how many failover buckets are provided.
  #
  # You can provide a list of HTTP status codes for failover criteria. We will default to using
  # all 4xx and 5xx status codes CloudFront provides.
  #
  # For more info, see:
  #
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html

  dynamic "origin_group" {
    for_each = length(var.failover_buckets) > 0 ? [1] : []
    iterator = failover_bucket

    content {
      origin_id = local.origin_group_id

      failover_criteria {
        status_codes = var.failover_status_codes
      }

      # Primary bucket member
      member {
        origin_id = var.bucket_name
      }

      # All Failover bucket members
      dynamic "member" {
        for_each = var.failover_buckets
        iterator = bucket

        content {
          origin_id = bucket.value
        }
      }
    }
  }

  # If you set the origin domain_name to <BUCKET_NAME>.s3-website-<AWS_REGION>.amazonaws.com (the S3 website URL),
  # CloudFront sees it as an arbitrary, opaque endpoint. It will only be able to talk to it over HTTP (since S3
  # websites don't support HTTPS) and you will have to make your bucket completely publicly accessible (you can't use
  # Origin Access Identity with arbitrary endpoints).
  #
  # The advantage of this is that all the S3 website features, such as routing and custom error pages, will work
  # correctly. Moreover, this approach works in any AWS region.
  #
  # For more info, see:
  #
  # http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistS3AndCustomOrigins.html
  # http://stackoverflow.com/a/22750923/483528
  #
  dynamic "origin" {
    for_each = local.all_buckets
    iterator = bucket

    content {
      domain_name = local.all_bucket_endpoints[bucket.key]

      origin_id   = bucket.value
      origin_path = var.s3_bucket_base_path

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = var.bucket_origin_config_protocol_policy
        origin_ssl_protocols   = var.bucket_origin_config_ssl_protocols
      }
    }
  }

  dynamic "logging_config" {
    for_each = length(module.access_logs) > 0 ? ["log"] : []

    content {
      include_cookies = var.include_cookies_in_logs
      bucket          = "${module.access_logs[0].name}.s3.amazonaws.com"
      prefix          = var.access_log_prefix
    }
  }

  default_cache_behavior {
    allowed_methods            = length(var.failover_buckets) > 0 ? var.allowed_origin_group_methods : var.allowed_methods
    cached_methods             = var.cached_methods
    compress                   = var.compress
    trusted_signers            = var.trusted_signers
    trusted_key_groups         = length(var.trusted_signers) > 0 ? [] : var.trusted_key_groups
    response_headers_policy_id = var.response_headers_policy_id

    default_ttl = var.default_ttl
    min_ttl     = var.min_ttl
    max_ttl     = var.max_ttl

    target_origin_id       = length(var.failover_buckets) > 0 ? local.origin_group_id : var.bucket_name
    viewer_protocol_policy = var.viewer_protocol_policy

    forwarded_values {
      query_string = var.forward_query_string
      headers      = var.forward_headers

      cookies {
        forward           = var.forward_cookies
        whitelisted_names = var.whitelisted_cookie_names
      }
    }

    dynamic "lambda_function_association" {
      for_each = var.default_lambda_associations

      content {
        event_type   = lambda_function_association.value.event_type
        include_body = lambda_function_association.value.include_body
        lambda_arn   = lambda_function_association.value.lambda_arn
      }
    }

    dynamic "function_association" {
      for_each = var.default_function_associations

      content {
        event_type   = function_association.value.event_type
        function_arn = function_association.value.function_arn
      }
    }
  }

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#cache-behavior-arguments
  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors
    content {
      # Required parameters
      allowed_methods        = ordered_cache_behavior.value.allowed_methods
      cached_methods         = ordered_cache_behavior.value.cached_methods
      path_pattern           = ordered_cache_behavior.value.path_pattern
      viewer_protocol_policy = ordered_cache_behavior.value.viewer_protocol_policy
      target_origin_id       = length(var.failover_buckets) > 0 ? local.origin_group_id : var.bucket_name

      # Optional parameters
      cache_policy_id            = lookup(ordered_cache_behavior.value, "cache_policy_id", null)
      compress                   = lookup(ordered_cache_behavior.value, "compress", null)
      default_ttl                = lookup(ordered_cache_behavior.value, "default_ttl", null)
      field_level_encryption_id  = lookup(ordered_cache_behavior.value, "field_level_encryption_id", null)
      max_ttl                    = lookup(ordered_cache_behavior.value, "max_ttl", null)
      min_ttl                    = lookup(ordered_cache_behavior.value, "min_ttl", null)
      origin_request_policy_id   = lookup(ordered_cache_behavior.value, "origin_request_policy_id", null)
      realtime_log_config_arn    = lookup(ordered_cache_behavior.value, "realtime_log_config_arn", null)
      response_headers_policy_id = lookup(ordered_cache_behavior.value, "response_headers_policy_id", null)
      smooth_streaming           = lookup(ordered_cache_behavior.value, "smooth_streaming", null)
      trusted_key_groups         = lookup(ordered_cache_behavior.value, "trusted_key_groups", null)
      trusted_signers            = lookup(ordered_cache_behavior.value, "trusted_signers", null)

      # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#forwarded-values-arguments
      dynamic "forwarded_values" {
        for_each = lookup(ordered_cache_behavior.value, "forwarded_values", [])
        content {
          headers                 = lookup(forwarded_values.value, "headers", null)
          query_string            = forwarded_values.value.query_string
          query_string_cache_keys = lookup(forwarded_values.value, "query_string_cache_keys", null)
          cookies {
            forward           = forwarded_values.value.cookies_forward
            whitelisted_names = lookup(forwarded_values.value, "cookies_whitelisted_names", null)
          }
        }
      }

      # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#lambda-function-association
      dynamic "lambda_function_association" {
        for_each = lookup(ordered_cache_behavior.value, "lambda_function_association", [])
        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.lambda_arn
          include_body = lookup(lambda_function_association.value, "include_body", null)
        }
      }

      # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution#function-association
      dynamic "function_association" {
        for_each = lookup(ordered_cache_behavior.value, "function_association", [])
        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.function_arn
        }
      }
    }
  } # end dynamic "ordered_cache_behavior"

  dynamic "custom_error_response" {
    for_each = var.error_responses != null ? var.error_responses : {}

    content {
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
      error_code            = custom_error_response.key
      response_code         = custom_error_response.value.response_code
      response_page_path    = "/${custom_error_response.value.response_page_path}"
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_locations_list
    }
  }

  viewer_certificate {
    minimum_protocol_version = var.minimum_protocol_version
    ssl_support_method       = local.is_acm_cert || local.is_iam_cert ? var.ssl_support_method : null
    acm_certificate_arn      = local.is_acm_cert ? var.acm_certificate_arn : null
    iam_certificate_id       = local.is_iam_cert ? var.iam_certificate_id : null

    # When an IAM or ACM cert is used, we won't use the default cert because a custom cert is provided. While setting
    # this to true has no effect, it causes a perpetual diff in the resource because the state returns as `false`.
    # See https://github.com/gruntwork-io/terraform-aws-static-assets/pull/26 for more context.
    cloudfront_default_certificate = local.is_acm_cert || local.is_iam_cert ? false : var.use_cloudfront_default_certificate
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ORIGIN ACCESS IDENTITY
# CloudFront will assume this identity when it makes requests to your origin servers. You can lock down your S3 bucket
# so it's not accessible directly, but only via CloudFront, by only allowing this identity to access the S3 bucket.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "For ${var.bucket_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN S3 BUCKET TO STORE ACCESS LOGS
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # In newer AWS accounts, you have to give permissions to the canonical ID of the AWS logs delivery account; in
  # older AWS accounts, you have to use the ARN of that account. If you use the wrong one, you get a perpetual diff
  # in the plan. See https://github.com/terraform-providers/terraform-provider-aws/issues/10158 for context.
  # We allow the user to tell us what to use based on the use_cloudfront_arn_for_bucket_policy variable. The
  # canonical ID comes from these docs:
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html. The ARN of that AWS account
  # doesn't seem to be documented anywhere; I got it from the perpetual diff itself, as this is the ARN AWS was
  # substituting in automatically instead of the ID. Hooray for magic numbers.
  policy_principal_type       = var.use_cloudfront_arn_for_bucket_policy ? "AWS" : "CanonicalUser"
  policy_principal_identifier = var.use_cloudfront_arn_for_bucket_policy ? ["arn:aws:iam::162777425019:root"] : ["c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"]
}

module "access_logs" {
  count  = var.disable_logging ? 0 : 1
  source = "git::git@github.com:gruntwork-io/terraform-aws-security.git//modules/private-s3-bucket?ref=v0.65.3"

  name              = "${var.bucket_name}-${var.access_logs_bucket_suffix}"
  acl               = "log-delivery-write"
  tags              = var.custom_tags
  sse_algorithm     = "AES256" # For access logging buckets, only AES256 encryption is supported
  enable_versioning = var.access_logs_enable_versioning
  force_destroy     = var.force_destroy_access_logs_bucket

  bucket_policy_statements = {
    # Create a policy that allows Cloudfront to write to the logs bucket
    # CloudFront automatically does this when you enable logging in the UI, but since we aren't using the UI, we have to
    # add these permissions ourselves. https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html
    AllowCloudfrontWriteS3AccessLog = {
      effect = "Allow"
      # It seems like CloudFront needs a lot of permissions to write the logs and set ACLs on them in this bucket
      actions = ["s3:*"]
      principals = {
        (local.policy_principal_type) = local.policy_principal_identifier
      }
    }
  }

  lifecycle_rules = {
    log = {
      prefix  = var.access_log_prefix
      enabled = true
      expiration = {
        expire_in_days = {
          days = var.access_logs_expiration_time_in_days
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# LOOK UP ZONE ID BY DOMAIN NAME
# ---------------------------------------------------------------------------------------------------------------------
data "aws_route53_zone" "selected" {
  // NOTE: If both var.hosted_zone_id and var.base_domain_name are provided, we will still only use var.base_domain_name
  // to lookup the zone id. This supports the use case where a customer wraps this module with a service module that
  // provides a hosted_zone_id that is computed. Because count is needed at plan time, terraform will fail in this case.
  // To mitigate this issue, the consumer should provide only var.hosted_zone_id and not var.base_domain_name if they
  // want to use var.hosted_zone_id.
  count = (var.create_route53_entries && var.base_domain_name != null) ? 1 : 0

  name         = var.base_domain_name
  tags         = var.base_domain_name_tags
  private_zone = var.private_zone
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONALLY CREATE ROUTE 53 ENTRIES FOR THE BUCKET
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_route53_record" "website" {
  count = (var.create_route53_entries ? 1 : 0) * length(var.domain_names)

  // If hosted_zone_id is provided, use that;
  // otherwise look up the zone_id based on base_domain_name and base_domain_name_tags
  zone_id = var.hosted_zone_id != null ? var.hosted_zone_id : data.aws_route53_zone.selected[0].zone_id
  name    = element(var.domain_names, count.index)
  type    = "A"

  alias {
    name = element(
      concat(
        aws_cloudfront_distribution.private_s3_bucket.*.domain_name,
        aws_cloudfront_distribution.public_website_s3_bucket.*.domain_name,
      ),
      0,
    )
    zone_id = element(
      concat(
        aws_cloudfront_distribution.private_s3_bucket.*.hosted_zone_id,
        aws_cloudfront_distribution.public_website_s3_bucket.*.hosted_zone_id,
      ),
      0,
    )
    evaluate_target_health = true
  }
}

# We create an AAAA record specifically for IPV6
# https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-cloudfront-distribution.html#routing-to-cloudfront-distribution-config
resource "aws_route53_record" "website_ipv6" {
  count = (var.create_route53_entries ? 1 : 0) * length(var.domain_names) * (var.is_ipv6_enabled ? 1 : 0)

  // If hosted_zone_id is provided, use that;
  // otherwise look up the zone_id based on base_domain_name and base_domain_name_tags
  zone_id = (var.create_route53_entries && var.hosted_zone_id != null ? var.hosted_zone_id : data.aws_route53_zone.selected[0].zone_id)
  name    = element(var.domain_names, count.index)
  type    = "AAAA"

  alias {
    name = element(
      concat(
        aws_cloudfront_distribution.private_s3_bucket.*.domain_name,
        aws_cloudfront_distribution.public_website_s3_bucket.*.domain_name,
      ),
      0,
    )
    zone_id = element(
      concat(
        aws_cloudfront_distribution.private_s3_bucket.*.hosted_zone_id,
        aws_cloudfront_distribution.public_website_s3_bucket.*.hosted_zone_id,
      ),
      0,
    )
    evaluate_target_health = true
  }
}
