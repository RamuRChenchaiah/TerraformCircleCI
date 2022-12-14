# S3 CloudFront Module

This module deploys a [CloudFront](https://aws.amazon.com/cloudfront/) distribution as a Content Distribution Network 
(CDN) in front of an [S3 bucket](https://aws.amazon.com/s3/). This reduces latency for your users, by caching your 
static content in servers around the world. It also allows you to use SSL with the static content in an S3 bucket. 

See the [s3-static-website module](/modules/s3-static-website) for how to deploy static content in an S3 bucket.  






## Quick Start

* See the [cloudfront-s3-public](/examples/cloudfront-s3-public) and 
  [cloudfront-s3-private](/examples/cloudfront-s3-private) examples for working sample code.
* Check out [vars.tf](vars.tf) for all parameters you can set for this module.




## Public vs private S3 buckets

This module can work with two types of S3 buckets:

* **Public S3 bucket**: You can use this module to deploy CloudFront in front of an S3 bucket that has been configured
  as a [website](http://docs.aws.amazon.com/AmazonS3/latest/dev/WebsiteHosting.html). This configuration allows you to
  configure [custom routing 
  rules](http://docs.aws.amazon.com/AmazonS3/latest/dev/HowDoIWebsiteConfiguration.html#configure-bucket-as-website-routing-rule-syntax),
  [custom error documents](http://docs.aws.amazon.com/AmazonS3/latest/dev/CustomErrorDocSupport.html) and other useful
  features for running a static website. The disadvantage is that you have to [make your S3 bucket publicly 
  accessible](http://docs.aws.amazon.com/AmazonS3/latest/dev/HostingWebsiteOnS3Setup.html#step2-add-bucket-policy-make-content-public),
  which means users who know the URL could access the bucket directly, bypassing CloudFront. Despite this minor 
  limitation, we recommend this option for most users, as it provides the best experience for running a website on S3. 
  To use this option, set the `s3_bucket_is_public_website` parameter to `true` and set the `bucket_website_endpoint`
  parameter to the publicly-accessible endpoint for your S3 website.

* **Private S3 bucket**: You can use this module to deploy CloudFront in front of a standard, private S3 bucket. The 
  advantage of this is that users can only access the contents of the S3 bucket by going via CloudFront (they can't 
  access the S3 bucket directly). The disadvantage is that you cannot use any of the S3 website features, such as 
  routing rules and custom error pages. This option is recommended if you have to keep the contents of the S3 bucket 
  secure (see also [Serving Private Content through 
  CloudFront](http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PrivateContent.html)). To use this 
  option, set the `s3_bucket_is_public_website` parameter to `false` and make sure to configure the IAM permissions
  for your S3 bucket to allow access from the CloudFront distributions Origin Access Identity, which is accessible
  via the `cloudfront_origin_access_identity_iam_arn` output variable.

**NOTE**: For some reason, the Private S3 bucket option currently ONLY works in `us-east1`. In all other regions, you 
get 403: Access Denied errors. We are still investigating why, but for the time being, deploy your entire static 
website in `us-east-1` and things will work fine.





## How do I test my website?

This module outputs the domain name of your website using the `cloudfront_domain_name` output variable.

By default, the domain name will be of the form:

```
<ID>.cloudfront.net
```

Where `ID` is a unique ID generated for your CloudFront distribution. For example:

```
d111111abcdef8.cloudfront.net
```

If you set `var.create_route53_entry` to true, then this module will create a DNS A record in [Route 
53](https://aws.amazon.com/route53/) for your CloudFront distribution with the domain name in 
`var.domain_name`, and you will be able to use that custom domain name to access your bucket instead of the 
`amazonaws.com` domain.




## How do I configure HTTPS (SSL)?

If you are using the default `.cloudfront.net` domain name, then you can use it with HTTPS with no extra changes:

```
https://<ID>.cloudfront.net
```

If you are using a custom domain name, to use HTTPS, you need to specify the ARN of either an [AWS Certificate Manager
(ACM)](https://aws.amazon.com/certificate-manager/) certificate via the `acm_certificate_arn` parameter or a 
custom [certificate in IAM](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_server-certs.html) via the
`iam_certificate_id` parameter. We recommend using ACM certs as they are free, very quick to set up, and best of all,
AWS automatically renews them for you. 

**NOTE**: If you set either `acm_certificate_arn` or `iam_certificate_id` you must set `use_cloudfront_default_certificate`
to `false`.


## Origin Group Support

This module can also create a CloudFront distribution that uses an Origin Group to serve content. The primary purpose of this is to have secondary bucket(s), which serve as a failover bucket in the event your primary bucket and/or its contents are not accessible.

### How To Configure
To use the Origin Group feature, you will need to provide values for the following variables:

* failover_buckets
* failover_bucket_website_endpoints (if making a public site)


## Limitations

To create a CloudFront distribution with Terraform, you use the [aws_cloudfront_distribution 
resource](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#viewer-certificate-arguments). 
Unfortunately, this resource primarily consists of "inline blocks", which do not work well in Terraform modules, as
there is no way to create them dynamically based on the module's inputs.

As a results, the CloudFront distribution in this module is limited to a fixed set of settings that should work for
most use cases, but is not particularly flexible. In particular, the limitations are as follows:

* Only one origin—an S3 bucket—is supported 
  ([origin](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#origin-arguments) is an inline
  block). You specify the bucket to use via the `bucket_name` parameter.
  
* Only one set of geo restrictions is supported 
  ([geo_restrictions](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#restrictions-arguments) 
  is an inline block). You can optionally specify the restrictions via the `geo_restriction_type` and 
  `geo_locations_list` parameters.
  
* Only one default cache behavior is supported 
  ([cache behaviors](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#cache-behavior-arguments) 
  is an inline block). You can control the default cache settings using a number of parameters, including 
  `cached_methods`, `default_ttl`, `min_ttl`, `max_ttl`, and many others (see [vars.tf](vars.tf) for the full list).
  
* Only two error responses are supported 
  ([error responses](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#custom-error-response-arguments)
  is an inline block). You can specify the 404 and 500 response paths using the `error_document_404` and 
  `error_document_500` parameters, respectively.
  
* You can not specify specify query string parameters to cache 
  ([query_string_cache_keys](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#query_string_cache_keys)
  is an inline block nested in an inline block).
  
* [custom_header](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#custom_header) is not
  yet supported as it consists of inline blocks in an inline block.

 * If configuring an Origin Group, due to an AWS limitation, only "GET", "HEAD", and "OPTIONS" methods are allowed for caching

If you absolutely need some of these features, the only solution available for now is to copy and paste this module
into your own codebase, using it as a guide, and adding the tweaks you need.
