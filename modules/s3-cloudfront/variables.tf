# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED MODULE PARAMETERS
# These variables must be passed in by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "bucket_name" {
  description = "The name of the S3 bucket."
  type        = string
}

variable "s3_bucket_is_public_website" {
  description = "Set to true if your S3 bucket is configured as a website and publicly accessible. Set to false if it's a regular S3 bucket and only privately accessible to CloudFront. If it's a public website, you can use all the S3 website features (e.g. routing, error pages), but users can bypass CloudFront and talk to S3 directly. If it's a private S3 bucket, users can only reach it via CloudFront, but you don't get all the website features."
  type        = string
}

variable "index_document" {
  description = "The path that you want CloudFront to query on the origin server when an end user requests the root URL (e.g. index.html)."
  type        = string
}

variable "default_ttl" {
  description = "The default amount of time, in seconds, that an object is in a CloudFront cache before CloudFront forwards another request in the absence of an 'Cache-Control max-age' or 'Expires' header."
  type        = number
}

variable "max_ttl" {
  description = "The maximum amount of time, in seconds, that an object is in a CloudFront cache before CloudFront forwards another request to your origin to determine whether the object has been updated. Only effective in the presence of 'Cache-Control max-age', 'Cache-Control s-maxage', and 'Expires' headers."
  type        = number
}

variable "min_ttl" {
  description = "The minimum amount of time that you want objects to stay in CloudFront caches before CloudFront queries your origin to see whether the object has been updated."
  type        = number
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "error_responses" {
  description = "The error responses you want CloudFront to return to the viewer."
  type = map(
    object({
      response_code         = number
      response_page_path    = string
      error_caching_min_ttl = number
    })
  )
  default = null
  # Example:
  #
  # default = {
  #   404 = {
  #     response_code         = 404
  #     response_page_path    = "404.html"
  #     error_caching_min_ttl = 0
  #   }
  # }
}

variable "ordered_cache_behaviors" {
  description = "An ordered list of cache behaviors resource for this distribution. List from top to bottom in order of precedence. The topmost cache behavior will have precedence 0."
  type        = list(any)
  # FIXME: This would be a lot better with optional parameters in terraform 1.3
  # https://developer.hashicorp.com/terraform/language/expressions/type-constraints#optional-object-type-attributes
  # REQUIRED
  # allowed_methods        - list(string) - Controls which HTTP methods CloudFront processes and forwards to your Amazon S3 bucket or your custom origin.
  # cached_methods         - list(string) - Controls whether CloudFront caches the response to requests using the specified HTTP methods.
  # path_pattern           - string - The pattern (for example, images/*.jpg) that specifies which requests you want this cache behavior to apply to.
  # viewer_protocol_policy - string - Use this element to specify the protocol that users can use to access the files in the origin specified by TargetOriginId when a request matches the path pattern in PathPattern. One of 'allow-all', 'https-only', or 'redirect-to-https'.
  #
  # OPTIONAL
  # cache_policy_id            - string - The unique identifier of the cache policy that is attached to the cache behavior.
  # compress                   - bool - Whether you want CloudFront to automatically compress content for web requests that include Accept-Encoding: gzip in the request header (default: false).
  # default_ttl                - number - The default amount of time (in seconds) that an object is in a CloudFront cache before CloudFront forwards another request in the absence of an Cache-Control max-age or Expires header.
  # field_level_encryption_id  - string - Field level encryption configuration ID
  # max_ttl                    - number - The maximum amount of time (in seconds) that an object is in a CloudFront cache before CloudFront forwards another request to your origin to determine whether the object has been updated. Only effective in the presence of Cache-Control max-age, Cache-Control s-maxage, and Expires headers.
  # min_ttl                    - number - The minimum amount of time that you want objects to stay in CloudFront caches before CloudFront queries your origin to see whether the object has been updated. Defaults to 0 seconds.
  # origin_request_policy_id   - string - The unique identifier of the origin request policy that is attached to the behavior.
  # realtime_log_config_arn    - string - The ARN of the real-time log configuration that is attached to this cache behavior.
  # response_headers_policy_id - string - The identifier for a response headers policy.
  # smooth_streaming           - string - Indicates whether you want to distribute media files in Microsoft Smooth Streaming format using the origin that is associated with this cache behavior.
  # trusted_key_groups         - string - A list of key group IDs that CloudFront can use to validate signed URLs or signed cookies. See the CloudFront User Guide for more information about this feature.
  # trusted_signers            - string - List of AWS account IDs (or self) that you want to allow to create signed URLs for private content. See the CloudFront User Guide for more information about this feature.
  #
  # forwarded_values (Optional) - A list of objects containing the forwarded values configuration that specifies how CloudFront handles query strings, cookies and headers (maximum one).
  #    cookies_forward (Required)           - string - Whether you want CloudFront to forward cookies to the origin that is associated with this cache behavior. You can specify 'all', 'none' or 'whitelist'. If 'whitelist', you must include the subsequent 'cookies_whitelisted_names'
  #    cookies_whitelisted_names (Optional) - list(string) - List of whitelisted cookies that you want CloudFront to forward to your origin. Only used if 'cookies_forward' is set to 'whitelist'.
  #    headers (Optional)                   - list(string) - Headers, if any, that you want CloudFront to vary upon for this cache behavior. Specify '*' to include all headers.
  #    query_string (Required)              - bool - Indicates whether you want CloudFront to forward query strings to the origin that is associated with this cache behavior.
  #    query_string_cache_keys (Optional)   - list(string) - When specified, along with a value of true for 'query_string', all query strings are forwarded, however only the query string keys listed in this argument are cached. When omitted with a value of true for 'query_string', all query string keys are cached.
  # 
  # lambda_function_association (Optional) - A list of objects that triggers a lambda function with specific actions (maximum 4).
  #   event_type (Required)   - string - The specific event to trigger this function. Valid values: 'viewer-request', 'origin-request', 'viewer-response', 'origin-response'
  #   lambda_arn (Required)   - string - ARN of the Lambda function.
  #   include_body (Optional) - bool - When set to true it exposes the request body to the lambda function.
  # 
  # function_association (Optional) - A list of objects that triggers a cloudfront function with specific actions (maximum 2).
  #   event_type (Required)   - string - The specific event to trigger this function. Valid values: viewer-request or viewer-response
  #   function_arn (Required) - string - ARN of the Cloudfront function.

  default = []
}

variable "failover_buckets" {
  description = "The list of the names of the failover S3 buckets. Provide if you wish to configure a CloudFront distribution with an Origin Group."
  type        = list(string)
  default     = []
}

variable "bucket_website_endpoint" {
  description = "The website endpoint for this S3 bucket. This value should be of the format <BUCKET_NAME>.s3-website-<AWS_REGION>.amazonaws.com. Only used if var.s3_bucket_is_public_website is true."
  type        = string
  default     = null
}

variable "failover_bucket_website_endpoints" {
  description = "The website endpoints for each failover S3 bucket. This value of each should be of the format <BUCKET_NAME>.s3-website-<AWS_REGION>.amazonaws.com. Only used if var.s3_bucket_is_public_website is true, and if you are providing a failover S3 bucket to be used in a CloudFront Origin Group configuration."
  type        = list(string)
  default     = []
}

variable "failover_status_codes" {
  description = "List of HTTP status codes to configure the Origin Group to fail over on. Provide if you wish to not failover on all provided 4xx and 5xx status codes."
  type        = list(number)
  default     = [500, 502, 503, 504, 404, 403]
}

variable "use_cloudfront_default_certificate" {
  description = "Set to true if you want viewers to use HTTPS to request your objects and you're using the CloudFront domain name for your distribution. You must set exactly one of var.use_cloudfront_default_certificate, var.acm_certificate_arn, or var.iam_certificate_id."
  type        = bool
  default     = true
}

variable "acm_certificate_arn" {
  description = "The ARN of the AWS Certificate Manager certificate that you wish to use with this distribution. The ACM certificate must be in us-east-1. You must set exactly one of var.use_cloudfront_default_certificate, var.acm_certificate_arn, or var.iam_certificate_id."
  type        = string
  default     = ""
}

variable "iam_certificate_id" {
  description = "The IAM certificate identifier of the custom viewer certificate for this distribution if you are using a custom domain. You must set exactly one of var.use_cloudfront_default_certificate, var.acm_certificate_arn, or var.iam_certificate_id."
  type        = string
  default     = ""
}

variable "create_route53_entries" {
  description = "If set to true, create a DNS A Record in Route 53 with each domain name in var.domain_names."
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "The ID of the Route 53 Hosted Zone in which to create the DNS A Records specified in var.domain_names. Only used if var.create_route53_entries is true."
  type        = string
  default     = null
}

variable "private_zone" {
  description = "Whether the Route 53 Hosted Zone associated with var.base_domain_name is private."
  type        = bool
  default     = false
}

variable "base_domain_name" {
  description = "The domain name associated with a hosted zone in Route 53. Usually the base domain name of one of the var.domain_names (e.g. foo.com). This is used to find the hosted zone that will be used for the CloudFront distribution."
  type        = string
  default     = null
}

variable "base_domain_name_tags" {
  description = "The tags associated with var.base_domain_name. If there are multiple hosted zones for the same base_domain_name, this will help filter the hosted zones so that the correct hosted zone is found."
  type        = map(any)
  default     = {}
}

variable "domain_names" {
  description = "The custom domain name to use instead of the default cloudfront.net domain name (e.g. static.foo.com). Only used if var.create_route53_entries is true."
  type        = list(string)
  default     = []
}

variable "allowed_methods" {
  description = "Controls which HTTP methods CloudFront will forward to the S3 bucket."
  type        = list(string)
  default     = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
}

variable "allowed_origin_group_methods" {
  description = "Controls which HTTP methods CloudFront will forward to Origin Group. Currently only allows GET,HEAD, and OPTIONS"
  type        = list(string)
  default     = ["GET", "HEAD", "OPTIONS"]
}

variable "cached_methods" {
  description = "CloudFront will cache the responses for these methods."
  type        = list(string)
  default     = ["GET", "HEAD"]
}

variable "compress" {
  description = "Whether you want CloudFront to automatically compress content for web requests that include 'Accept-Encoding: gzip' in the request header."
  type        = bool
  default     = true
}

variable "viewer_protocol_policy" {
  description = "Use this element to specify the protocol that users can use to access the files in the origin specified by TargetOriginId when a request matches the path pattern in PathPattern. One of allow-all, https-only, or redirect-to-https."
  type        = string
  default     = "allow-all"
}

variable "forward_query_string" {
  description = "Indicates whether you want CloudFront to forward query strings to the origin. If set to true, CloudFront will cache all query string parameters."
  type        = bool
  default     = true
}

variable "forward_cookies" {
  description = "Specifies whether you want CloudFront to forward cookies to the origin that is associated with this cache behavior. You can specify all, none or whitelist. If whitelist, you must define var.whitelisted_cookie_names."
  type        = string
  default     = "none"
}

variable "whitelisted_cookie_names" {
  description = "If you have specified whitelist in var.forward_cookies, the whitelisted cookies that you want CloudFront to forward to your origin."
  type        = list(string)
  default     = []
}

variable "forward_headers" {
  description = "The headers you want CloudFront to forward to the origin. Set to * to forward all headers."
  type        = list(string)
  default     = []
}

variable "s3_bucket_base_path" {
  description = "If set, CloudFront will request all content from the specified folder, rather than the root of the S3 bucket."
  type        = string
  default     = null
}

variable "enabled" {
  description = "Whether the distribution is enabled to accept end user requests for content."
  type        = bool
  default     = true
}

variable "is_ipv6_enabled" {
  description = "Whether the IPv6 is enabled for the distribution."
  type        = bool
  default     = true
}

variable "http_version" {
  description = "The maximum HTTP version to support on the distribution. Allowed values are http1.1 and http2."
  type        = string
  default     = "http2"
}

variable "price_class" {
  description = "The price class for this distribution. One of PriceClass_All, PriceClass_200, PriceClass_100. Higher price classes support more edge locations, but cost more. See: https://aws.amazon.com/cloudfront/pricing/#price-classes."
  type        = string
  default     = "PriceClass_100"
}

variable "web_acl_id" {
  description = "If you're using AWS WAF to filter CloudFront requests, the Id of the AWS WAF web ACL that is associated with the distribution."
  type        = string
  default     = null
}

variable "disable_logging" {
  description = "Option to disable cloudfront log delivery to s3.  This is required in regions where cloudfront cannot deliver logs to s3, see https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html#access-logs-choosing-s3-bucket"
  type        = bool
  default     = false
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

variable "access_logs_bucket_suffix" {
  description = "The suffix for the access logs bucket where logs should be written."
  type        = string
  default     = "cloudfront-logs"
}

variable "access_logs_enable_versioning" {
  description = "Set to true to enable versioning for the access logs S3 bucket. If enabled, instead of overriding objects, the S3 bucket will always create a new version of each object, so all the old values are retained."
  type        = bool
  default     = false
}

variable "force_destroy_access_logs_bucket" {
  description = "If set to true, this will force the delete of the access logs S3 bucket when you run terraform destroy, even if there is still content in it. This is only meant for testing and should not be used in production."
  type        = bool
  default     = false
}

variable "geo_restriction_type" {
  description = "The method that you want to use to restrict distribution of your content by country: none, whitelist, or blacklist."
  type        = string
  default     = "none"
}

variable "geo_locations_list" {
  description = "The ISO 3166-1-alpha-2 codes for which you want CloudFront either to distribute your content (if var.geo_restriction_type is whitelist) or not distribute your content (if var.geo_restriction_type is blacklist)."
  type        = list(string)
  default     = []
}

variable "minimum_protocol_version" {
  description = "The minimum version of the SSL protocol that you want CloudFront to use for HTTPS connections. One of SSLv3 or TLSv1. Default: SSLv3. NOTE: If you are using a custom certificate (specified with acm_certificate_arn or iam_certificate_id), and have specified sni-only in ssl_support_method, TLSv1 must be specified."
  type        = string
  default     = "TLSv1"
}

variable "ssl_support_method" {
  description = "Specifies how you want CloudFront to serve HTTPS requests. One of vip or sni-only. Required if you specify acm_certificate_arn or iam_certificate_id. NOTE: vip causes CloudFront to use a dedicated IP address and may incur extra charges."
  type        = string
  default     = "sni-only"
}

variable "trusted_signers" {
  description = "The list of AWS account IDs that you want to allow to create signed URLs for private content."
  type        = list(string)
  default     = []
}

variable "trusted_key_groups" {
  description = "The list of key group IDs that CloudFront can use to validate signed URLs or signed cookies. Only used if trusted_signers is empty."
  type        = list(string)
  default     = []
}

variable "include_cookies_in_logs" {
  description = "Specifies whether you want CloudFront to include cookies in access logs."
  type        = bool
  default     = false
}

variable "custom_tags" {
  description = "A map of custom tags to apply to the S3 bucket and Cloudfront Distribution. The key is the tag name and the value is the tag value."
  type        = map(string)
  default     = {}
}

variable "default_lambda_associations" {
  description = "A list of existing Lambda@Edge functions to associate with the default cached behavior. Lambda version must be a published version and cannot be `$LATEST` (See https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#lambda_function_association for available options)."

  type = list(object({
    event_type   = string
    lambda_arn   = string
    include_body = bool
  }))

  default = []
}

variable "default_function_associations" {
  description = "A list of existing CloudFront functions to associate with the default cached behavior. CloudFront functions are lightweight alternatives to Lambda for high-scale, latency sensitive CDN customizations"

  type = list(object({
    event_type   = string
    function_arn = string
  }))

  default = []
}

variable "use_cloudfront_arn_for_bucket_policy" {
  description = "In older AWS accounts, you must set this variable to true to use the ARN of the CloudFront log delivery AWS account in the access log bucket policy. In newer AWS accounts, you must set this variable to false to use the CanonicalUser ID of the CloudFront log delivery account. If you pick the wrong value, you'll get a perpetual diff on the IAM policy. See https://github.com/terraform-providers/terraform-provider-aws/issues/10158 for context."
  type        = bool
  default     = false
}

variable "wait_for_deployment" {
  description = "If enabled, the resource will wait for the distribution status to change from InProgress to Deployed, which can take quite a long time in Cloudfront's case. Setting this to false will skip the process."
  type        = bool
  default     = true
}

variable "bucket_origin_config_protocol_policy" {
  description = "The origin protocol policy to apply to the S3 bucket origin. Must be one of http-only, https-only, and match-viewer."
  type        = string
  default     = "http-only"
}

variable "bucket_origin_config_ssl_protocols" {
  description = "The SSL/TLS protocols that you want CloudFront to use when communicating with the S3 bucket over HTTPS. A list of one or more of SSLv3, TLSv1, TLSv1.1, and TLSv1.2."
  type        = list(string)
  default     = ["TLSv1.2"]
}

variable "response_headers_policy_id" {
  description = "ID of response headers policy to apply to this CloudFront distribution."
  type        = string
  default     = null
}

variable "additional_bucket_information" {
  # Additional s3 bucket information to support buckets in other regions, also with v4 Auth support only.
  #
  # A Map with the bucket name as key and the additional information as properties:
  #
  # - region    (string) - (Optional) Region of the bucket. Required, if v4_auth is true.
  # - v4_auth   (bool)   - (Optional) Use v4 Authentication
  description = "A Map with the bucket name as key and the additional information about region and v4_auth as values."
  type = map(object({
    region  = string
    v4_auth = bool
  }))
  default = {}

  # Example:
  # {
  #   bucket-name = {
  #     region  = "eu-central-1"
  #     v4_auth = true
  #   }
  # }
}
