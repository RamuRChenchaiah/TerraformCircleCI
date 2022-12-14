# S3 Static Website Example

This folder shows an example of how to use the [s3-static-website module](/modules/s3-static-website) to launch a
static website on top of S3. 





## Quick start

To try these templates out you must have Terraform installed:

1. Open `vars.tf`, set the environment variables specified at the top of the file, and fill in any other variables that
   don't have a default.
1. Run `terraform get`.
1. Run `terraform plan`.
1. If the plan looks good, run `terraform apply`.

When the `apply` command finishes, this module will output the domain name you can use to test the website in your
browser.





