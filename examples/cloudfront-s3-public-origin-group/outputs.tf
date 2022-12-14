output "cloudfront_domain_names" {
  value = module.cloudfront.cloudfront_domain_names
}

output "cloudfront_id" {
  value = module.cloudfront.cloudfront_id
}

output "cloudfront_access_logs_bucket_arn" {
  value = module.cloudfront.access_logs_bucket_arn
}

output "website_s3_bucket_arn" {
  value = module.static_website.website_bucket_arn
}

output "website_access_logs_bucket_arn" {
  value = module.static_website.access_logs_bucket_arn
}

output "failover_website_s3_bucket_arn" {
  value = module.failover_static_website.website_bucket_arn
}

output "failover_website_access_logs_bucket_arn" {
  value = module.failover_static_website.access_logs_bucket_arn
}
