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

# This is set to type 'any' so we can do dynamic lookups of individual parameters within each rule.
# This allows the optional parameters in the block to be left out and fall back to default values.
# Using type of 'list' enforces all items are the same exact type, which would prevent users from
# skipping optional parameters.
variable "cors_rule" {
  description = "A configuration for CORS on the S3 bucket. Default value comes from AWS. Can override for custom CORS by passing the object structure define in the documentation https://www.terraform.io/docs/providers/aws/r/s3_bucket.html#using-cors."
  type        = any
  default     = []
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

variable "restrict_access_to_cloudfront" {
  description = "If set to true, the S3 bucket will only be accessible via CloudFront, and not directly. You must specify var.cloudfront_origin_access_identity_iam_arn if you set this variable to true."
  type        = bool
  default     = false
}

variable "cloudfront_origin_access_identity_s3_canonical_user_id" {
  description = "The ID of the s3 Canonical User for Cloudfront Origin Identity. Only used if var.restrict_access_to_cloudfront is true. See: https://docs.aws.amazon.com/AmazonS3/latest/dev/example-bucket-policies.html#example-bucket-policies-use-case-6. If you are getting a perpetual diff, set var.cloudfront_origin_access_identity_iam_arn."
  type        = string
  default     = null
}

variable "cloudfront_origin_access_identity_iam_arn" {
  description = "The IAM ARN of the CloudFront origin access identity. Only used if var.restrict_access_to_cloudfront is true. In older AWS accounts, you must use this in place of var.cloudfront_origin_access_identity_s3_canonical_user_id. Otherwise, you will end up with a perpetual diff on the IAM policy. See https://github.com/terraform-providers/terraform-provider-aws/issues/10158 for context."
  type        = string
  default     = null
}

variable "enable_versioning" {
  description = "Set to true to enable versioning. This means the bucket will retain all old versions of all files. This is useful for backup purposes (e.g. you can rollback to an older version), but it may mean your bucket uses more storage."
  type        = bool
  default     = true
}

variable "routing_rule" {
  # The routing rule for this S3 bucket website configuration. See the 'routing_rule' block in the aws_s3_bucket_website_configuration resource for context:
  # https://registry.terraform.io/providers/hashicorp/aws/3.75.0/docs/resources/s3_bucket_website_configuration
  #
  # routing_rule is a map with a condition map and a redirect map.
  #
  # The condition map must have at least one of the following properties:
  #
  # - http_error_code_returned_equals             string       (optional): The HTTP error code when the redirect is applied. If specified with key_prefix_equals, then both must be true for the redirect to be applied.
  # - key_prefix_equals                           string       (optional): The object key name prefix when the redirect is applied. If specified with http_error_code_returned_equals, then both must be true for the redirect to be applied.
  #
  # The redirect map can have the following properties:
  #
  # - host_name                                   string       (optional): The hostname to use in the redirect request.
  # - http_redirect_code                          string       (optional): The HTTP redirect code to use on the response.
  # - protocol                                    string       (optional): Protocol to use when redirecting requests. The default is the protocol that is used in the original request. Valid values: http, https.
  # - replace_key_prefix_with                     string       (optional): Conflicts with replace_key_with. The object key prefix to use in the redirect request.
  # - replace_key_with                            string       (optional): Conflicts with replace_key_prefix_with. The specific object key to use in the redirect request.
  description = "A map describing the routing_rule for the aws_s3_website_configuration resource. Describes redirect behavior and conditions when redirects are applied."
  # Ideally, this would be a map(object({...})), but the Terraform object type constraint doesn't support optional
  # parameters, whereas routing rules have many optional params. And we can't even use map(any), as the Terraform
  # map type constraint requires all values to have the same type ("shape"), but as each object in the map may specify
  # different optional params, this won't work either. So, sadly, we are forced to fall back to "any."
  type = any
  # Example:
  #
  # {
  #    condition = {
  #      key_prefix_equals  = "docs/"
  #    }
  #
  #    redirect = {
  #      host_name = "example"
  #      http_redirect_code = "403"
  #      protocol = "https"
  #      replace_key_prefix_with = "documents/"
  #    }
  # }
  #
  # Example:
  #
  # {
  #    condition = {
  #      http_error_code_returned_equals = "401"
  #    }
  #
  #    redirect = {
  #      replace_key_with = "error.html"
  #    }
  # }
  #
  default = {}
}

variable "create_route53_entry" {
  description = "If set to true, create a DNS A Record in Route 53 with the domain name in var.website_domain_name. If you're using CloudFront, you should configure the domain name in the CloudFront module and not in this module."
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "The ID of the Route 53 Hosted Zone in which to create the DNS A Record specified in var.website_domain_name. Only used if var.create_route53_entry is true."
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

variable "should_redirect_all_requests" {
  description = "If set to true, this implies that this S3 bucket is only for redirecting all requests to another domain name specified in var.redirect_all_requests_to. This is useful to setup a bucket to redirect, for example, foo.com to www.foo.com."
  type        = bool
  default     = false
}

variable "server_side_encryption_configuration" {
  description = "A configuration for server side encryption (SSE) on the S3 bucket. Defaults to AES256. The list should contain the object structure defined in the documentation https://www.terraform.io/docs/providers/aws/r/s3_bucket.html#enable-default-server-side-encryption. To opt out of encryption set the variable to an empty list []."
  type        = list(any)

  default = [
    {
      rule = [
        {
          apply_server_side_encryption_by_default = [
            {
              sse_algorithm     = "AES256"
              kms_master_key_id = ""
            },
          ]
        },
      ]
    },
  ]
}

variable "redirect_all_requests_to" {
  description = "A string of the URL to redirect all requests to. Only used if var.should_redirect_all_requests is true."
  type        = string
  default     = null
}

variable "access_logs_expiration_time_in_days" {
  description = "How many days to keep access logs around for before deleting them."
  type        = number
  default     = 30
}

variable "access_log_prefix" {
  description = "The folder in the access logs bucket where logs should be written."
  type        = string
  default     = null
}

variable "access_logs_kms_key_arn" {
  description = "Optional KMS key to use for encrypting data in the access logs S3 bucket. If null, data in the access logs S3 bucket will be encrypted using the default aws/s3 key. If provided, the key policy of the provided key must allow whoever is writing to this bucket to use that key."
  type        = string
  default     = null
}

variable "access_logs_sse_algorithm" {
  description = "The server-side encryption algorithm to use on data in the access logs S3 bucket. Valid values are AES256 and aws:kms."
  type        = string
  default     = "aws:kms"
}

variable "access_logs_enable_versioning" {
  description = "Set to true to enable versioning for the access logs S3 bucket. If enabled, instead of overriding objects, the S3 bucket will always create a new version of each object, so all the old values are retained."
  type        = bool
  default     = false
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

variable "force_destroy_access_logs_bucket" {
  description = "If set to true, this will force the delete of the access logs S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
  type        = bool
  default     = false
}

variable "custom_tags" {
  description = "A map of custom tags to apply to the S3 bucket. The key is the tag name and the value is the tag value."
  type        = map(string)
  default     = {}
}

variable "add_random_id_name_suffix" {
  description = "Whether the bucket should have a random string appended to the name (by default a random string is not appended)"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  # The lifecycle rules for this S3 bucket. See the 'lifecycle_rule' block in the aws_s3_bucket resource for context:
  # https://registry.terraform.io/providers/hashicorp/aws/3.75.0/docs/resources/s3_bucket
  #
  # lifecycle_rules is a map where the keys are the IDs of the rules and the values are objects that can define the
  # following properties:
  #
  # - enabled                                     bool              (required): Specifies lifecycle rule status.
  # - prefix                                      string            (optional): Object key prefix identifying one or more objects to which the rule applies.
  # - tags                                        map(string)       (optional): Specifies object tags key and value.
  # - abort_incomplete_multipart_upload_days      number            (optional): Specifies the number of days after initiating a multipart upload when the multipart upload must be completed.
  # - noncurrent_version_expiration               number            (optional): Specifies the number of days noncurrent object versions expire.
  # - expiration                                  map(object)       (optional): Specifies a period in the object's expire (documented below).
  # - transition                                  map(object)       (optional): Specifies a period in the object's transitions (documented below).
  # - noncurrent_version_transition               map(object)       (optional): Specifies when noncurrent object versions transitions (documented below).
  #
  # expiration is a map from a unique ID for the expiration setting to an object that can define the following properties:
  #
  # - date                                        string            (optional): Specifies the date after which you want the corresponding action to take effect.
  # - days                                        number            (optional): Specifies the number of days after object creation when the specific rule action takes effect.
  # - expired_object_delete_marker                string            (optional): On a versioned bucket (versioning-enabled or versioning-suspended bucket), you can add this element in the lifecycle configuration to direct Amazon S3 to delete expired object delete markers.
  #
  # transition is a map from a unique ID for the transition setting to an object that can define the following properties:
  #
  # - storage_class                               string            (required): Specifies the Amazon S3 storage class to which you want the object to transition. Can be ONEZONE_IA, STANDARD_IA, INTELLIGENT_TIERING, GLACIER, or DEEP_ARCHIVE.
  # - date                                        string            (optional): Specifies the date after which you want the corresponding action to take effect.
  # - days                                        number            (optional): Specifies the number of days after object creation when the specific rule action takes effect.
  #
  # noncurrent_version_transition is a map from a unique ID for the noncurrent_version_transition setting to an object that can define the following properties:
  #
  # - storage_class                               string            (required): Specifies the Amazon S3 storage class to which you want the noncurrent object versions to transition. Can be ONEZONE_IA, STANDARD_IA, INTELLIGENT_TIERING, GLACIER, or DEEP_ARCHIVE.
  # - days                                        number            (required): Specifies the number of days noncurrent object versions transition.
  description = "The lifecycle rules for this S3 bucket. These can be used to change storage types or delete objects based on customizable rules. This should be a map, where each key is a unique ID for the lifecycle rule, and each value is an object that contains the parameters defined in the comment above."

  # Ideally, this would be a map(object({...})), but the Terraform object type constraint doesn't support optional
  # parameters, whereas lifecycle rules have many optional params. And we can't even use map(any), as the Terraform
  # map type constraint requires all values to have the same type ("shape"), but as each object in the map may specify
  # different optional params, this won't work either. So, sadly, we are forced to fall back to "any."
  type = any
  # Example:
  #
  # {
  #    ExampleRule = {
  #      prefix  = "config/"
  #      enabled = true
  #
  #      noncurrent_version_transition = {
  #        ToStandardIa = {
  #          days          = 30
  #          storage_class = "STANDARD_IA"
  #        }
  #        ToGlacier = {
  #          days          = 60
  #          storage_class = "GLACIER"
  #        }
  #      }
  #
  #      noncurrent_version_expiration = 90
  #    }
  # }
  default = {}
}

variable "s3_bucket_object_ownership" {
  description = "The S3 bucket object ownership. Valid values are BucketOwnerPreferred, ObjectWriter or BucketOwnerEnforced. https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html"
  type        = string
  default     = "ObjectWriter"
}

variable "s3_bucket_override_policy_documents" {
  description = "List of IAM policy documents, in stringified JSON format, that are merged into the S3 bucket policy."
  type        = list(string)
  default     = null
}
