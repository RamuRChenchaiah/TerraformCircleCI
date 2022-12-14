package test

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestS3CloudfrontCanonicalUser(t *testing.T) {
	t.Parallel()

	//os.Setenv("SKIP_setup", "true")
	//os.Setenv("SKIP_apply", "true")
	//os.Setenv("SKIP_validate", "true")
	//os.Setenv("SKIP_destroy", "true")

	var testcases = []struct {
		testName     string
		terraformDir string
	}{
		{
			"TestCloudFrontS3PrivateExampleForCanonicalUser",
			"cloudfront-s3-private",
		},
	}

	for _, testCase := range testcases {
		testCase := testCase

		t.Run(testCase.testName, func(t *testing.T) {

			workingDir := filepath.Join(".", "stages", t.Name())

			testFolder := test_structure.CopyTerraformFolderToTemp(t, "../", filepath.Join("examples", testCase.terraformDir))

			test_structure.RunTestStage(t, "setup", func() {
				uniqueID := strings.ToLower(random.UniqueId())
				test_structure.SaveString(t, workingDir, "uniqueID", uniqueID)

				awsRegion := "us-east-1"
				test_structure.SaveString(t, workingDir, "awsRegion", awsRegion)

				awsAccountID := aws.GetAccountId(t)
				test_structure.SaveString(t, workingDir, "accountID", awsAccountID)
			})

			uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")
			awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
			awsAccountID := test_structure.LoadString(t, workingDir, "accountID")

			terraformOptions := &terraform.Options{
				TerraformDir: testFolder,
				Vars: map[string]interface{}{
					"aws_region":                           awsRegion,
					"aws_account_id":                       awsAccountID,
					"website_domain_name":                  FormatDomainName("cloudfront-example", uniqueID),
					"create_route53_entry":                 true,
					"hosted_zone_id":                       HOSTED_ZONE_ID_FOR_TEST,
					"acm_certificate_domain_name":          ACM_CERT_DOMAIN_NAME_FOR_TEST,
					"force_destroy_access_logs_bucket":     true,
					"force_destroy_redirect":               true,
					"force_destroy_website":                true,
					"use_canonical_iam_user_for_s3":        true,
					"use_cloudfront_arn_for_bucket_policy": true,
				},
			}

			defer test_structure.RunTestStage(t, "destroy", func() {
				terraform.Destroy(t, terraformOptions)
			})

			test_structure.RunTestStage(t, "apply", func() {
				terraform.InitAndApply(t, terraformOptions)

				// Canonical User is the recommended way from AWS to grant Cloudfront access to a private S3 bucket:
				// https://docs.aws.amazon.com/AmazonS3/latest/dev/example-bucket-policies.html#example-bucket-policies-use-case-6
				//
				// Due to a bug, when canonical user is used it results in a perpetual diff, as behind the scenes
				// AWS converts the bucket policy from canonical user to an Origin Identity Access ARN.
				// https://github.com/terraform-providers/terraform-provider-aws/issues/10158
				//
				// When this fix is made, this test should be updated to check for perpetual diffs.

				// 	exitCode := terraform.PlanExitCode(t, terraformOptions)
				// 	assert.Equal(t, 0, exitCode)
			})

			test_structure.RunTestStage(t, "validate", func() {
				initialMaxRetries := 270
				maxRetries := 10
				sleepBetweenRetries := 10 * time.Second

				testWebsite(t, "http", "cloudfront_domain_names", "", 200, "Hello, World!", initialMaxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)
				testWebsite(t, "https", "cloudfront_domain_names", "", 200, "Hello, World!", maxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)
				testWebsite(t, "http", "cloudfront_domain_names", "not-a-valid-path", 404, "Uh oh", maxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)
				testWebsite(t, "https", "cloudfront_domain_names", "not-a-valid-path", 404, "Uh oh", maxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)
			})
		})
	}
}
