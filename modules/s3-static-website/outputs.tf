output "website_bucket_name" {
  value = var.should_redirect_all_requests ? aws_s3_bucket.redirect[0].id : aws_s3_bucket.website[0].id
}

output "website_domain_name" {
  value = var.create_route53_entry ? join(",", aws_route53_record.website.*.fqdn) : element(
    concat(
      aws_s3_bucket.website.*.website_endpoint,
      aws_s3_bucket.redirect.*.website_endpoint,
      [""], // Adding empty list element to account for partial destroy, then destroying again
    ),
    0,
  )
}

output "website_bucket_arn" {
  value = element(
    concat(
      aws_s3_bucket.website.*.arn,
      aws_s3_bucket.redirect.*.arn,
      [""], // Adding empty list element to account for partial destroy, then destroying again
    ),
    0,
  )
}

output "website_bucket_endpoint" {
  value = element(
    concat(
      aws_s3_bucket_website_configuration.website.*.website_endpoint,
      aws_s3_bucket_website_configuration.redirect.*.website_endpoint,
      [""], // Adding empty list element to account for partial destroy, then destroying again
    ),
    0,
  )
}

output "access_logs_bucket_arn" {
  value = module.access_logs.arn
}

output "website_bucket_is_fully_configured" {
  description = "A value that can be used to chain resources to depend on the website bucket being fully configured with all the configuration resources created. The value is always true, as the bucket would be fully configured when Terraform is able to render this."
  value = (
    length(compact(flatten([
      aws_s3_bucket_acl.website[*].id,
      aws_s3_bucket_cors_configuration.website[*].id,
      aws_s3_bucket_lifecycle_configuration.bucket[*].id,
      aws_s3_bucket_logging.website[*].id,
      aws_s3_bucket_server_side_encryption_configuration.website[*].id,
      aws_s3_bucket_versioning.website[*].id,
      aws_s3_bucket_policy.website[*].id,
      aws_s3_bucket_website_configuration.website[*].id,
      aws_s3_bucket_ownership_controls.website[*].id,
    ]))) > 0
    ? true
    : true
  )
}

output "redirect_bucket_is_fully_configured" {
  description = "A value that can be used to chain resources to depend on the redirect bucket being fully configured with all the configuration resources created. The value is always true, as the bucket would be fully configured when Terraform is able to render this."
  value = (
    length(compact(flatten([
      aws_s3_bucket_acl.redirect[*].id,
      aws_s3_bucket_logging.redirect[*].id,
      aws_s3_bucket_versioning.redirect[*].id,
      aws_s3_bucket_policy.redirect[*].id,
      aws_s3_bucket_website_configuration.redirect[*].id,
    ]))) > 0
    ? true
    : true
  )
}

# All the above domain names are virtual-host-style domain names of the format <bucket-name>.s3.amazonaws.com, which
# only work over HTTP. This output uses a path-style domain name of the format s3-<region>.amazonaws.com/<bucket-name>,
# which will work over both HTTP and HTTPS. For more info, see:
# https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingBucket.html#access-bucket-intro
output "website_bucket_endpoint_path_style" {
  value = "${lookup(
    local.bucket_regional_endpoint_exceptions_map,
    data.aws_region.current.name,
    "s3-${data.aws_region.current.name}",
  )}.amazonaws.com/${var.website_domain_name}"
}

locals {
  # For most AWS regions, the S3 path-style URL will be of the format s3-<region>.amazonaws.com. However, there are a
  # few exceptions, which we capture in this map. https://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region
  bucket_regional_endpoint_exceptions_map = {
    "us-east-1" = "s3" # us-east-1 URLs are of the format s3.amazonaws.com (no region suffix).
  }
}

data "aws_region" "current" {}
