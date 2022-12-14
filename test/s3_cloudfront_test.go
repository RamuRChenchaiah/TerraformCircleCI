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
	cleanhttp "github.com/hashicorp/go-cleanhttp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestS3Cloudfront(t *testing.T) {
	t.Parallel()

	//os.Setenv("SKIP_setup", "true")
	//os.Setenv("SKIP_apply", "true")
	//os.Setenv("SKIP_validate", "true")
	//os.Setenv("SKIP_destroy", "true")

	var testcases = []struct {
		testName          string
		terraformDir      string
		checkCustomHeader bool
	}{
		{
			"TestCloudFrontS3PrivateExample",
			"cloudfront-s3-private",
			false,
		},
		{
			"TestCloudFrontS3PublicExample",
			"cloudfront-s3-public",
			true,
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
					"use_cloudfront_arn_for_bucket_policy": true,
				},
			}

			if strings.HasSuffix(testCase.terraformDir, "public") {
				terraformOptions.Vars["lambda_name_prefix"] = uniqueID
			}

			defer test_structure.RunTestStage(t, "destroy", func() {
				terraform.Destroy(t, terraformOptions)
			})

			test_structure.RunTestStage(t, "apply", func() {
				terraform.InitAndApply(t, terraformOptions)

				// Test for perpetual diff: plan should exit with exitcode 0 if there are no changes to make.
				exitCode := terraform.PlanExitCode(t, terraformOptions)
				assert.Equal(t, 0, exitCode)
			})

			test_structure.RunTestStage(t, "validate", func() {
				initialMaxRetries := 270
				maxRetries := 10
				sleepBetweenRetries := 10 * time.Second

				testWebsite(t, "http", "cloudfront_domain_names", "", 200, "Hello, World!", initialMaxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)
				testWebsite(t, "https", "cloudfront_domain_names", "", 200, "Hello, World!", maxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)
				testWebsite(t, "http", "cloudfront_domain_names", "not-a-valid-path", 404, "Uh oh", maxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)
				testWebsite(t, "https", "cloudfront_domain_names", "not-a-valid-path", 404, "Uh oh", maxRetries, sleepBetweenRetries, terraformOptions, testCase.testName)

				if testCase.checkCustomHeader {
					// Make sure that the response header includes the custom header injected by lambda@edge function
					domainNameArr := terraform.OutputList(t, terraformOptions, "cloudfront_domain_names")
					domainName := domainNameArr[0]
					url := fmt.Sprintf("https://%s/", domainName)
					client := cleanhttp.DefaultClient()
					resp, err := client.Get(url)
					require.NoError(t, err)
					customHeader, hasCustomHeader := resp.Header["X-Custom-Header"]
					require.True(t, hasCustomHeader)
					assert.Equal(t, []string{"hello from lambda!"}, customHeader)
				}
			})
		})
	}
}
