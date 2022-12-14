# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# SETUP AN S3 BUCKET TO HOST A STATIC WEBSITE
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
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # We will use this logic to determine the bucket name to use
  bucket_name = length(random_id.bucket) > 0 ? random_id.bucket[0].hex : var.website_domain_name
  create_acl  = var.s3_bucket_object_ownership != "BucketOwnerEnforced"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE S3 BUCKET FOR HOSTING THE WEBSITE
# Note that this bucket is only created if var.should_redirect_all_requests is false.
# ---------------------------------------------------------------------------------------------------------------------

resource "random_id" "bucket" {
  count       = var.add_random_id_name_suffix ? 1 : 0
  byte_length = 4
  prefix      = "${var.website_domain_name}-"
}

resource "aws_s3_bucket" "website" {
  count = var.should_redirect_all_requests ? 0 : 1

  bucket        = local.bucket_name
  force_destroy = var.force_destroy_website
  tags          = var.custom_tags

  lifecycle {
    ignore_changes = [
      server_side_encryption_configuration,
      logging,
      versioning,
      lifecycle_rule,
      cors_rule,
      website,

      # This is referencing the rule instead of the block as recommended in the AWS provider docs:
      # https://registry.terraform.io/providers/hashicorp/aws/3.75.1/docs/resources/s3_bucket_object_lock_configuration#usage-notes
      object_lock_configuration[0].rule,
    ]
  }
}

# For 4.x forward compatibility:
# Routing rules must be provided as this new map format.
resource "aws_s3_bucket_website_configuration" "website" {
  count = var.should_redirect_all_requests ? 0 : 1

  bucket = aws_s3_bucket.website[0].id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }

  dynamic "routing_rule" {
    for_each = var.routing_rule

    content {
      dynamic "condition" {
        for_each = lookup(var.routing_rule, "condition", {})

        content {
          http_error_code_returned_equals = lookup(var.routing_rule.condition, "http_error_code_returned_equals", null)
          key_prefix_equals               = lookup(var.routing_rule.condition, "key_prefix_equals", null)
        }
      }

      redirect {
        host_name               = lookup(var.routing_rule.redirect, "host_name", null)
        http_redirect_code      = lookup(var.routing_rule.redirect, "http_redirect_code", null)
        protocol                = lookup(var.routing_rule.redirect, "protocol", null)
        replace_key_prefix_with = lookup(var.routing_rule.redirect, "replace_key_prefix_with", null)
        replace_key_with        = lookup(var.routing_rule.redirect, "replace_key_with", null)
      }
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  count = var.should_redirect_all_requests ? 0 : 1

  bucket = aws_s3_bucket.website[0].id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  count = var.should_redirect_all_requests || length(var.lifecycle_rules) <= 0 ? 0 : 1

  bucket = aws_s3_bucket.website[0].id

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id     = rule.key
      status = lookup(rule.value, "enabled", null) == true ? "Enabled" : "Disabled"

      dynamic "abort_incomplete_multipart_upload" {
        for_each = lookup(rule.value, "abort_incomplete_multipart_upload_days", null) != null ? ["once"] : []

        content {
          days_after_initiation = lookup(rule.value, "abort_incomplete_multipart_upload_days", null)
        }
      }

      # For 3.x backward compatibility:
      # Create an and filter when tags are provided, even if prefix is not provided, to match the 3.x provider logic.
      # See https://github.com/hashicorp/terraform-provider-aws/blob/v3.74.3/internal/service/s3/bucket.go#L2242-L2249
      dynamic "filter" {
        for_each = lookup(rule.value, "tags", null) != null ? ["once"] : []

        content {
          and {
            prefix = lookup(rule.value, "prefix", null)
            tags   = lookup(rule.value, "tags", null)
          }
        }
      }

      # For 3.x backward compatibility:
      # Create a prefix-only filter when tags are not provided, even if prefix is not provided, to match the 3.x
      # provider logic.
      # See https://github.com/hashicorp/terraform-provider-aws/blob/v3.74.3/internal/service/s3/bucket.go#L2242-L2249
      dynamic "filter" {
        for_each = lookup(rule.value, "tags", null) == null ? ["once"] : []

        content {
          prefix = lookup(rule.value, "prefix", null)
        }
      }

      dynamic "expiration" {
        for_each = lookup(rule.value, "expiration", {})

        content {
          date                         = lookup(expiration.value, "date", null)
          days                         = lookup(expiration.value, "days", null)
          expired_object_delete_marker = lookup(expiration.value, "expired_object_delete_marker ", null)
        }
      }

      dynamic "transition" {
        for_each = lookup(rule.value, "transition", {})

        content {
          storage_class = lookup(transition.value, "storage_class")
          date          = lookup(transition.value, "date", null)
          days          = lookup(transition.value, "days", null)
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = lookup(rule.value, "noncurrent_version_expiration", null) != null ? ["once"] : []

        content {
          noncurrent_days = lookup(rule.value, "noncurrent_version_expiration")
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = lookup(rule.value, "noncurrent_version_transition", {})

        content {
          noncurrent_days = lookup(noncurrent_version_transition.value, "days")
          storage_class   = lookup(noncurrent_version_transition.value, "storage_class")
        }
      }
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "website" {
  count = !var.should_redirect_all_requests && length(var.cors_rule) > 0 ? 1 : 0

  bucket = aws_s3_bucket.website[0].id

  dynamic "cors_rule" {
    for_each = var.cors_rule

    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }
}

resource "aws_s3_bucket_acl" "website" {
  count = var.should_redirect_all_requests || !local.create_acl ? 0 : 1

  bucket = aws_s3_bucket.website[0].id
  acl    = var.restrict_access_to_cloudfront ? "private" : "public-read"
}

resource "aws_s3_bucket_logging" "website" {
  count = var.should_redirect_all_requests ? 0 : 1

  bucket        = aws_s3_bucket.website[0].id
  target_bucket = module.access_logs.name

  # target_prefix was optional in provider version 3.x, but is now required so cannot be null.
  # To keep provider version 4.x support backward compatible, default to "" when var.access_log_prefix is null.
  target_prefix = var.access_log_prefix == null ? "" : var.access_log_prefix
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  count = (
    !var.should_redirect_all_requests
    && length(var.server_side_encryption_configuration) > 0
    ? 1
    : 0
  )

  bucket = aws_s3_bucket.website[0].id

  dynamic "rule" {
    for_each = lookup(var.server_side_encryption_configuration[0], "rule", [])

    content {
      bucket_key_enabled = false

      dynamic "apply_server_side_encryption_by_default" {
        for_each = lookup(rule.value, "apply_server_side_encryption_by_default", [])

        content {
          kms_master_key_id = lookup(apply_server_side_encryption_by_default.value, "kms_master_key_id", null)
          sse_algorithm     = apply_server_side_encryption_by_default.value.sse_algorithm
        }
      }
    }
  }
}

resource "aws_s3_bucket_versioning" "website" {
  count = var.should_redirect_all_requests ? 0 : 1

  bucket = aws_s3_bucket.website[0].id

  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Suspended"
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "website" {
  count = var.should_redirect_all_requests ? 0 : 1

  bucket = aws_s3_bucket.website[0].id
  rule {
    object_ownership = var.s3_bucket_object_ownership
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# WHEN PRIVATE MODE, BLOCK ALL POSSIBILITY OF ACCIDENTALLY ENABLING PUBLIC ACCESS TO THIS BUCKET
# ----------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "public_access" {
  count = var.restrict_access_to_cloudfront && !var.should_redirect_all_requests ? 1 : 0

  bucket                  = aws_s3_bucket.website[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE S3 BUCKET FOR REDIRECTS
# Note that this bucket is only created if var.should_redirect_all_requests is true. Unfortunately, Terraform does not
# let you simply set the redirect_all_requests_to parameter to an empty string. If you set it at all, you can't set
# index_document or error_document or routing_rule. Therefore, we need two aws_s3_bucket resources.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "redirect" {
  count = var.should_redirect_all_requests ? 1 : 0

  bucket        = local.bucket_name
  force_destroy = var.force_destroy_redirect
  tags          = var.custom_tags

  lifecycle {
    ignore_changes = [
      server_side_encryption_configuration,
      logging,
      versioning,
      lifecycle_rule,
      cors_rule,
      website,

      # This is referencing the rule instead of the block as recommended in the AWS provider docs:
      # https://registry.terraform.io/providers/hashicorp/aws/3.75.1/docs/resources/s3_bucket_object_lock_configuration#usage-notes
      object_lock_configuration[0].rule,
    ]
  }
}

locals {
  # Calculate the host_name and protocol for the redirect_all_requests_to block.
  redirect_url_split = (
    var.should_redirect_all_requests
    && var.redirect_all_requests_to != null
    ? split("://", var.redirect_all_requests_to)
    : []
  )

  # If a protocol is provided in the input string, parse it out and provide it.
  redirect_all_protocol = (
    length(local.redirect_url_split) > 1
    ? local.redirect_url_split[0]
    : null
  )

  # If a protocol is provided, parse out the host_name as the part after it.
  redirect_all_host_name = (
    length(local.redirect_url_split) > 1
    ? local.redirect_url_split[1]
    : var.redirect_all_requests_to
  )

  redirect_all_map = {
    host_name = local.redirect_all_host_name
    protocol  = local.redirect_all_protocol
  }
}

resource "aws_s3_bucket_website_configuration" "redirect" {
  count = var.should_redirect_all_requests ? 1 : 0

  bucket = aws_s3_bucket.redirect[0].id

  # For 4.x forward compatibility:
  # Calculate redirect_all_requests_to map of host_name and optional protocol using string input.
  redirect_all_requests_to {
    host_name = local.redirect_all_map.host_name
    protocol  = local.redirect_all_map.protocol
  }
}

resource "aws_s3_bucket_acl" "redirect" {
  count = var.should_redirect_all_requests ? 1 : 0

  bucket = aws_s3_bucket.redirect[0].id
  acl    = "public-read"
}

resource "aws_s3_bucket_versioning" "redirect" {
  count = var.should_redirect_all_requests ? 1 : 0

  bucket = aws_s3_bucket.redirect[0].id

  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Suspended"
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_logging" "redirect" {
  count = var.should_redirect_all_requests ? 1 : 0

  bucket        = aws_s3_bucket.redirect[0].id
  target_bucket = module.access_logs.name

  # target_prefix was optional in provider version 3.x, but is now required so cannot be null.
  # To keep provider version 4.x support backward compatible, default to "" when var.access_log_prefix is null.
  target_prefix = var.access_log_prefix == null ? "" : var.access_log_prefix
}

resource "aws_s3_bucket_policy" "redirect" {
  count = var.should_redirect_all_requests ? 1 : 0

  bucket = aws_s3_bucket.redirect[0].id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

# ---------------------------------------------------------------------------------------------------------------------
# BUCKET POLICY
# Create appropriate bucket policy depending on whether this is a 'public' or 'cloudfront only' bucket. If supplied,
# merge in a user-defined IAM Policy as well.
# Note: Policies in source_policy_documents that do not have a SID cannot be overridden and are merged as per terraform
# documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
# ---------------------------------------------------------------------------------------------------------------------

# Public bucket policy: This policy allows everyone to view the S3 bucket directly. This is only created if
# var.restrict_access_to_cloudfront is false.
data "aws_iam_policy_document" "public_bucket_policy" {
  count = var.restrict_access_to_cloudfront ? 0 : 1

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.bucket_name}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }

  override_policy_documents = var.s3_bucket_override_policy_documents
}

# CloudFront only bucket policy: This policy allows only CloudFront to access the S3 bucket directly, so everyone else
# must go via the CDN. This is only created if var.limit_access_to_cloudfront is true.
locals {
  bucket_policy_statements_for_cf = [
    {
      actions   = ["s3:GetObject"]
      resources = ["arn:aws:s3:::${local.bucket_name}/*"]
    },
    {
      actions   = ["s3:ListBucket"]
      resources = ["arn:aws:s3:::${local.bucket_name}"]
    }
  ]

  bucket_policy_statements_for_user = var.cloudfront_origin_access_identity_s3_canonical_user_id != null ? local.bucket_policy_statements_for_cf : []
  bucket_policy_statements_for_arn  = var.cloudfront_origin_access_identity_iam_arn != null ? local.bucket_policy_statements_for_cf : []
}

data "aws_iam_policy_document" "cloudfront_only_bucket_policy" {
  count = var.restrict_access_to_cloudfront ? 1 : 0

  dynamic "statement" {
    for_each = local.bucket_policy_statements_for_arn

    content {
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources

      principals {
        type        = "AWS"
        identifiers = [var.cloudfront_origin_access_identity_iam_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = local.bucket_policy_statements_for_user

    content {
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources

      principals {
        type        = "CanonicalUser"
        identifiers = [var.cloudfront_origin_access_identity_s3_canonical_user_id]
      }
    }
  }

  override_policy_documents = var.s3_bucket_override_policy_documents
}

data "aws_iam_policy_document" "enforce_tls" {
  count = var.restrict_access_to_cloudfront ? 1 : 0

  # Require that all access to this bucket is over TLS
  statement {
    sid     = "AllowTLSRequestsOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = (
      length(aws_s3_bucket.website) > 0
      ? [
        aws_s3_bucket.website[0].arn,
        "${aws_s3_bucket.website[0].arn}/*",
      ]
      : [
        aws_s3_bucket.redirect[0].arn,
        "${aws_s3_bucket.redirect[0].arn}/*",
      ]
    )
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Combine the individual bucket policies into one.
data "aws_iam_policy_document" "s3_bucket_policy" {
  source_policy_documents = concat(
    data.aws_iam_policy_document.cloudfront_only_bucket_policy.*.json,
    data.aws_iam_policy_document.public_bucket_policy.*.json,
    data.aws_iam_policy_document.enforce_tls.*.json,
  )
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
  count = (var.create_route53_entry && var.base_domain_name != null) ? 1 : 0

  name = var.base_domain_name
  tags = var.base_domain_name_tags

  private_zone = var.private_zone
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SEPARATE S3 BUCKET TO STORE ACCESS LOGS
# Note that we use the private-s3-bucket module here to create the S3 bucket, as the access logs bucket should be
# completely private. However, the S3 bucket for the static website is a public bucket, so we don't use the same
# module for it.
# ---------------------------------------------------------------------------------------------------------------------

module "access_logs" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-security.git//modules/private-s3-bucket?ref=v0.65.3"

  name              = "${local.bucket_name}-logs"
  acl               = "log-delivery-write"
  tags              = var.custom_tags
  kms_key_arn       = var.access_logs_kms_key_arn
  sse_algorithm     = var.access_logs_sse_algorithm
  enable_versioning = var.access_logs_enable_versioning
  force_destroy     = var.force_destroy_access_logs_bucket

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
# OPTIONALLY CREATE A ROUTE 53 ENTRY FOR THE BUCKET
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_route53_record" "website" {
  count = var.create_route53_entry ? 1 : 0

  // If hosted_zone_id is provided, use that;
  // otherwise look up the zone_id based on base_domain_name and base_domain_name_tags
  zone_id = var.hosted_zone_id != null ? var.hosted_zone_id : data.aws_route53_zone.selected[0].zone_id
  name    = local.bucket_name
  type    = "A"

  alias {
    name = element(
      concat(
        aws_s3_bucket_website_configuration.website.*.website_domain,
        aws_s3_bucket_website_configuration.redirect.*.website_domain,
      ),
      0,
    )
    zone_id = element(
      concat(
        aws_s3_bucket.website.*.hosted_zone_id,
        aws_s3_bucket.redirect.*.hosted_zone_id,
      ),
      0,
    )
    evaluate_target_health = true
  }
}
