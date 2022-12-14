package test

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
)

func TestS3CloudfrontCustomBucketPolicy(t *testing.T) {
	t.Parallel()

	// For convenience - uncomment these as well as the "os" import
	// when doing local testing if you need to skip any sections.
	// os.Setenv("TERRATEST_REGION", "us-east-1")
	// os.Setenv("SKIP_setup_terraform_options", "true")
	// os.Setenv("SKIP_deploy_to_aws_and_validate", "true")
	// os.Setenv("SKIP_check_perpetual_diff", "true")
	// os.Setenv("SKIP_teardown", "true")

	testName := "TestCloudFrontS3CustomBucketPolicy"
	terraformDir := "cloudfront-s3-private-with-custom-bucket-policy"

	examplesDir := test_structure.CopyTerraformFolderToTemp(t, "../", "examples")

	test_structure.RunTestStage(t, "setup_terraform_options", func() {
		uniqueBaseName := strings.ToLower(random.UniqueId())
		test_structure.SaveString(t, examplesDir, "unique-id", uniqueBaseName)

		awsRegion := "us-east-1"

		awsAccountID := aws.GetAccountId(t)

		terraformOptions := &terraform.Options{
			// The path to where your Terraform code is located
			TerraformDir: filepath.Join(examplesDir, terraformDir),
			Vars: map[string]interface{}{
				"aws_region":                           awsRegion,
				"aws_account_id":                       awsAccountID,
				"website_domain_name":                  FormatDomainName("cloudfront-example", uniqueBaseName),
				"create_route53_entry":                 true,
				"hosted_zone_id":                       HOSTED_ZONE_ID_FOR_TEST,
				"acm_certificate_domain_name":          ACM_CERT_DOMAIN_NAME_FOR_TEST,
				"force_destroy_access_logs_bucket":     true,
				"force_destroy_redirect":               true,
				"force_destroy_website":                true,
				"use_cloudfront_arn_for_bucket_policy": true,
				"principal_arn":                        fmt.Sprintf("arn:aws:iam::%s:role/allow-full-access-from-other-accounts", awsAccountID),
			},
		}

		test_structure.SaveTerraformOptions(t, examplesDir, terraformOptions)
	})

	defer test_structure.RunTestStage(t, "teardown", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, examplesDir)
		terraform.Destroy(t, terraformOptions)
	})

	test_structure.RunTestStage(t, "deploy_to_aws_and_validate", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, examplesDir)
		terraform.InitAndApply(t, terraformOptions)

		initialMaxRetries := 270
		maxRetries := 10
		sleepBetweenRetries := 10 * time.Second

		testWebsite(t, "http", "cloudfront_domain_names", "", 200, "Hello, World!", initialMaxRetries, sleepBetweenRetries, terraformOptions, testName)
		testWebsite(t, "https", "cloudfront_domain_names", "", 200, "Hello, World!", maxRetries, sleepBetweenRetries, terraformOptions, testName)
		testWebsite(t, "http", "cloudfront_domain_names", "not-a-valid-path", 404, "Uh oh", maxRetries, sleepBetweenRetries, terraformOptions, testName)
		testWebsite(t, "https", "cloudfront_domain_names", "not-a-valid-path", 404, "Uh oh", maxRetries, sleepBetweenRetries, terraformOptions, testName)
	})

	test_structure.RunTestStage(t, "check_perpetual_diff", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, examplesDir)
		exitCode := terraform.PlanExitCode(t, terraformOptions)
		assert.Equal(t, exitCode, 0)
	})
}
