# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED MODULE PARAMETERS
# These variables must be passed in by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region in which all resources will be created"
  type        = string

  # NOTE: currently, this example ONLY works in us-east-1, so do not change this!
  default = "us-east-1"
}

variable "aws_account_id" {
  description = "The AWS account to deploy into."
  type        = string
}

variable "website_domain_name" {
  description = "The name of the website and the S3 bucket to create (e.g. static.foo.com)."
  type        = string
}

variable "create_route53_entry" {
  description = "If set to true, create a DNS A Record in Route 53 with the domain name in var.website_domain_name."
  type        = bool
}

variable "hosted_zone_id" {
  description = "The ID of the Route 53 Hosted Zone in which to create the DNS A Record specified in var.domain_name. Only used if var.create_route53_entry is true. Set to blank otherwise."
  type        = string
}

variable "acm_certificate_domain_name" {
  description = "The domain name for which an ACM cert has been issues (e.g. *.foo.com).  Only used if var.create_route53_entry is true. Set to blank otherwise."
  type        = string
}

variable "principal_arn" {
  description = "Principal ARN allowed PutObject via the S3 bucket policy."
  type        = string
  # default = "arn:aws:iam::222222222222:user/Jane"
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "force_destroy_access_logs_bucket" {
  description = "If set to true, this will force the delete of the access logs S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
  type        = bool
  default     = false
}

variable "force_destroy_redirect" {
  description = "If set to true, this will force the delete of the redirect S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
  type        = bool
  default     = false
}

variable "force_destroy_website" {
  description = "If set to true, this will force the delete of the website S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
  type        = bool
  default     = false
}

variable "index_document" {
  description = "The path to the index document in the S3 bucket (e.g. index.html)."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "The path to the error document in the S3 bucket (e.g. error.html)."
  type        = string
  default     = "error.html"
}

variable "use_canonical_iam_user_for_s3" {
  description = "If set to true, this will use the S3 Canonical user allowing access from Cloudfront to the bucket. Otherwise the IAM arn will be used. See: https://docs.aws.amazon.com/AmazonS3/latest/dev/example-bucket-policies.html#example-bucket-policies-use-case-6"
  type        = bool
  default     = false
}

variable "use_cloudfront_arn_for_bucket_policy" {
  description = "In older AWS accounts, you must set this variable to true to use the ARN of the CloudFront log delivery AWS account in the access log bucket policy. In newer AWS accounts, you must set this variable to false to use the CanonicalUser ID of the CloudFront log delivery account. If you pick the wrong value, you'll get a perpetual diff on the IAM policy. See https://github.com/terraform-providers/terraform-provider-aws/issues/10158 for context."
  type        = bool
  default     = false
}
