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

variable "website_domain_name" {
  description = "The name of the website and the S3 bucket to create (e.g. static.foo.com)."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region in which all resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "force_destroy_access_logs_bucket" {
  description = "If set to true, this will force the delete of the access logs S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
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

variable "create_route53_entry" {
  description = "If set to true, create a DNS A Record in Route 53 with the domain name in var.domain_name. If you're using CloudFront, you should configure the domain name in the CloudFront module and not in this module."
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "The ID of the Route 53 Hosted Zone in which to create the DNS A Record specified in var.domain_name. Only used if var.create_route53_entry is true."
  type        = string
  default     = null
}

variable "private_zone" {
  description = "Whether the Route 53 Hosted Zone associated with var.base_domain_name is private."
  type        = bool
  default     = false
}

variable "base_domain_name" {
  description = "The domain name associated with a hosted zone in Route 53. Usually the base domain name of one of the var.website_domain_name (e.g. foo.com). This is used to find the hosted zone that will be used for the CloudFront distribution."
  type        = string
  default     = null
}

variable "base_domain_name_tags" {
  description = "The tags associated with var.base_domain_name. If there are multiple hosted zones for the same base_domain_name, this will help filter the hosted zones so that the correct hosted zone is found."
  type        = map(any)
  default     = {}
}

variable "force_destroy_website" {
  description = "If set to true, this will force the delete of the website S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
  type        = bool
  default     = false
}

variable "force_destroy_redirect" {
  description = "If set to true, this will force the delete of the redirect S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
  type        = bool
  default     = false
}

variable "add_random_id_name_suffix" {
  description = "Whether the bucket should have a random string appended to the name (by default a random string is not appended)"
  type        = bool
  default     = false
}
