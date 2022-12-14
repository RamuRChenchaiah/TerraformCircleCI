output "cloudfront_domain_names" {
  value = split(
    ",",
    var.create_route53_entries ? join(",", aws_route53_record.website.*.fqdn) : element(
      concat(
        aws_cloudfront_distribution.private_s3_bucket.*.domain_name,
        aws_cloudfront_distribution.public_website_s3_bucket.*.domain_name,
        [""] // Adding empty list element to account for partial destroy, then destroying again
      ),
      0,
    ),
  )
}

output "cloudfront_id" {
  value = element(
    concat(
      aws_cloudfront_distribution.private_s3_bucket.*.id,
      aws_cloudfront_distribution.public_website_s3_bucket.*.id,
      [""] // Adding empty list element to account for partial destroy, then destroying again
    ),
    0,
  )
}

output "cloudfront_distribution_domain_name" {
  value = element(
    concat(
      aws_cloudfront_distribution.private_s3_bucket.*.domain_name,
      aws_cloudfront_distribution.public_website_s3_bucket.*.domain_name,
      [""] // Adding empty list element to account for partial destroy, then destroying again
    ),
    0,
  )
}

output "cloudfront_distribution_arn" {
  value = element(
    concat(
      aws_cloudfront_distribution.private_s3_bucket.*.arn,
      aws_cloudfront_distribution.public_website_s3_bucket.*.arn,
      [""] // Adding empty list element to account for partial destroy, then destroying again
    ),
    0,
  )
}

output "cloudfront_origin_access_identity_iam_arn" {
  value = aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn
}

output "cloudfront_origin_access_identity_s3_canonical_user_id" {
  value = aws_cloudfront_origin_access_identity.origin_access_identity.s3_canonical_user_id
}

output "access_logs_bucket_arn" {
  value = length(module.access_logs) > 0 ? module.access_logs[0].arn : null
}

