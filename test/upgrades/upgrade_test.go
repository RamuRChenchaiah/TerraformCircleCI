package upgrades

import (
	"testing"

	"github.com/gruntwork-io/module-ci/test/upgrades"
	"github.com/gruntwork-io/terraform-aws-static-assets/test"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// The following lists are to keep track of which of the examples we've added upgrade tests for,
// and which modules we've tested upgrading. Commented ones are not covered in upgrade tests yet.
var examplesToTest = upgrades.ExampleConfig{
	// "cloudfront-s3-private",
	"cloudfront-s3-private-origin-group": {
		SetupFn: setupForCloudFrontS3PrivateOriginGroup,
	},
	// "cloudfront-s3-private-with-custom-bucket-policy",
	// "cloudfront-s3-public",
	// "cloudfront-s3-public-origin-group",
	"s3-static-website": {
		SetupFn: setupForS3StaticWebsite,
	},
}

var modulesToTest = []string{
	"s3-cloudfront",
	"s3-static-website",
}

func TestUpgradeModules(t *testing.T) {
	config := upgrades.UpgradeModuleTestConfig{
		RepoName:      "terraform-aws-static-assets",
		ModulesToTest: modulesToTest,
		ExampleConfig: examplesToTest,
	}

	upgrades.RunUpgradeModuleTests(t, config)
}

func setupForCloudFrontS3PrivateOriginGroup(t *testing.T, workingDir string, uniqueID string) *terraform.Options {
	awsAccountID := aws.GetAccountId(t)

	terraformOptions := &terraform.Options{
		Vars: map[string]interface{}{
			"aws_region":                           "us-east-1",
			"aws_account_id":                       awsAccountID,
			"website_domain_name":                  test.FormatDomainName("cf-example", uniqueID),
			"failover_website_domain_names":        []string{test.FormatDomainName("cf-example-failover", uniqueID)},
			"create_route53_entries":               true,
			"hosted_zone_id":                       test.HOSTED_ZONE_ID_FOR_TEST,
			"acm_certificate_domain_name":          test.ACM_CERT_DOMAIN_NAME_FOR_TEST,
			"force_destroy_access_logs_bucket":     true,
			"force_destroy_redirect":               true,
			"force_destroy_website":                true,
			"use_cloudfront_arn_for_bucket_policy": true,
		},
		Upgrade: true,
	}
	return terraformOptions
}

func setupForS3StaticWebsite(t *testing.T, workingDir string, uniqueID string) *terraform.Options {
	awsRegion := aws.GetRandomStableRegion(t, []string{}, []string{})

	terraformOptions := &terraform.Options{
		Vars: map[string]interface{}{
			"aws_region":                       awsRegion,
			"website_domain_name":              test.FormatDomainName("", uniqueID),
			"create_route53_entry":             true,
			"hosted_zone_id":                   test.HOSTED_ZONE_ID_FOR_TEST,
			"force_destroy_access_logs_bucket": true,
			"force_destroy_website":            true,
			"force_destroy_redirect":           true,
		},
		Upgrade: true,
	}
	return terraformOptions
}
