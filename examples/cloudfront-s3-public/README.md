# CloudFront + S3 public website example

This folder shows an example of how to use the [s3-cloudfront](/modules/s3-cloudfront) and 
[s3-static-website](/modules/s3-static-website) modules to deploy a CloudFront distribution as a CDN in front of a 
public S3 bucket configured as a website. Make sure to read the [Public vs private S3 buckets 
documentation](/modules/s3-cloudfront#public-vs-private-s3-buckets) to understand the difference between this example
and the [cloudfront-s3-private example](/examples/cloudfront-s3-private).






## Quick start

To try these templates out you must have Terraform installed:

1. Open `vars.tf`, set the environment variables specified at the top of the file, and fill in any other variables that
   don't have a default.
1. Run `terraform get`.
1. Run `terraform plan`.
1. If the plan looks good, run `terraform apply`.

When the `apply` command finishes, this module will output the domain name you can use to test the website in your
browser. 

Note that a CloudFront distribution can take a LONG time to deploy (i.e. sometimes as much as 15 - 30 minutes!), so 
before testing the URL, head over to the [CloudFront distributions 
page](https://console.aws.amazon.com/cloudfront/home#distributions:) and wait for the "Status" of your distribution
to show up as "Deployed".





