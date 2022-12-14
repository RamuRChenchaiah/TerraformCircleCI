
## Quick Start

* See the [s3-static-website example](/examples/s3-static-website) for working sample code.
* Check out [vars.tf](vars.tf) for all parameters you can set for this module.

## How to test the website?

This module outputs the domain name of your website using the `website_domain_name` output variable.

By default, the domain name will be of the form:

```
<BUCKET_NAME>.s3-website-<AWS_REGION>.amazonaws.com/
```

Where `BUCKET_NAME` is the name you specified for the bucket and `AWS_REGION` is the region you created the bucket in.
For example, if the bucket was called `foo` and you deployed it in `us-east-1`, the URL would be:

```
foo.s3-website-us-east-1.amazonaws.com
```

If you set `var.create_route53_entry` to true, then this module will create a DNS A record in [Route 
53](https://aws.amazon.com/route53/) for your S3 bucket with the domain name in `var.website_domain_name`, and you will 
be able to use that custom domain name to access your bucket instead of the `amazonaws.com` domain.

## How to configure HTTPS (SSL) or a CDN?

By default, the static content in an S3 bucket is only accessible over HTTP. To be able to access it over HTTPS, you
need to deploy a CloudFront distribution in front of the S3 bucket. This will also act as a Content Distribution
Network (CDN), which will reduce latency for your users. You will need to set the `use_with_cloudfront` parameter to
`true`.

To set up a CloudFront distribution, see the [s3-cloudfront module](/modules/s3-cloudfront).

## How do I handle www + root domains?

If you are using your S3 bucket for both the `www.` and root domain of a website (e.g. `www.foo.com` and `foo.com`),
you need to create two buckets. One of the buckets contains the actual static content. The other sets the 
`should_redirect_all_requests` parameter to `true` and sets the `redirect_all_requests_to` parameter to the URL of the
first site. See the [Setting Up a Static Website Using a Custom 
Domain](http://docs.aws.amazon.com/AmazonS3/latest/dev/website-hosting-custom-domain-walkthrough.html) documentation
for more info.

[foo](#how-do-i-configure-cross-origin-resource-sharing-cors)

## How do I configure Cross Origin Resource Sharing (CORS)?

To enable [Cross Origin Resource Sharing (CORS)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS), you need to
set the `cors_rule` parameter in this module:

```hcl
module "s3_static_website" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-static-assets.git//modules/s3-static-website?ref=<VERSION>"

  # ... other params omitted ...

  # CORS settings
  cors_rule = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["www.your-domain.com"]
      expose_headers  = ["ETag","Origin","Access-Control-Request-Headers","Access-Control-Request-Method"]
      max_age_seconds = 3000
    },
    
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["www.another-domain.com"]
      expose_headers  = ["ETag","Origin","Access-Control-Request-Headers","Access-Control-Request-Method"]
      max_age_seconds = 3000
    }
  ]  
}

```

**NOTE #1**: due to a [bug in Terraform](https://github.com/terraform-providers/terraform-provider-aws/issues/9334), you
CANNOT pass multiple origins in the `allowed_origins` parameter! Instead, add a separate entry to `cors_rule` for each
origin.

**NOTE #2**: if you're also using the `s3-cloudfront` module, you MUST forward the `Origin` header using the 
`forward_headers` parameter or CORS won't work!

```hcl
module "s3_cloudfront" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-static-assets.git//modules/s3-cloudfront?ref=<VERSION>"
  
  # ... other params omitted ...

  # MUST be specified or CORS won't work
  forward_headers = ["Origin"]
}
```