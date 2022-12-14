package test

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
)

func TestS3StaticWebsite(t *testing.T) {
	t.Parallel()

	testName := "s3-website-example"

	//os.Setenv("TERRATEST_REGION", "us-east-1")
	//os.Setenv("SKIP_setup", "true")
	//os.Setenv("SKIP_apply", "true")
	//os.Setenv("SKIP_validate", "true")
	//os.Setenv("SKIP_destroy", "true")

	var testcases = []struct {
		testName           string
		createRoute53Entry bool
	}{
		{
			"TestS3StaticWebsiteWithRoute53Entry",
			true,
		},
		// TODO: Add test for NoRoute53Entry.
		// Currently, this example does not work unless create_route53_entry = true.
	}

	for _, testCase := range testcases {

		testCase := testCase

		t.Run(testCase.testName, func(t *testing.T) {

			workingDir := filepath.Join(".", "stages", t.Name())

			testFolder := test_structure.CopyTerraformFolderToTemp(t, "../", "examples/s3-static-website")

			test_structure.RunTestStage(t, "setup", func() {
				awsRegion := aws.GetRandomRegion(t, []string{"us-east-2"}, []string{"ap-southeast-1", "sa-east-1"})
				test_structure.SaveString(t, workingDir, "awsRegion", awsRegion)

				uniqueID := random.UniqueId()
				test_structure.SaveString(t, workingDir, "uniqueID", uniqueID)
			})

			awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
			uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")

			terraformOptions := &terraform.Options{
				TerraformDir: testFolder,
				Vars: map[string]interface{}{
					"aws_region":                       awsRegion,
					"website_domain_name":              FormatDomainName(testName, uniqueID),
					"create_route53_entry":             testCase.createRoute53Entry,
					"hosted_zone_id":                   HOSTED_ZONE_ID_FOR_TEST,
					"force_destroy_access_logs_bucket": true,
					"force_destroy_website":            true,
					"force_destroy_redirect":           true,
				},
			}

			defer test_structure.RunTestStage(t, "destroy", func() {
				terraform.Destroy(t, terraformOptions)
			})

			test_structure.RunTestStage(t, "apply", func() {
				terraform.InitAndApply(t, terraformOptions)

				// Test for perpetual diff.
				exitCode := terraform.PlanExitCode(t, terraformOptions)
				assert.Equal(t, 0, exitCode)
			})

			test_structure.RunTestStage(t, "validate", func() {
				maxRetries := 10
				sleepBetweenRetries := 10 * time.Second

				testWebsite(t, "http", "website_domain_name", "", 200, "Hello, World!", maxRetries, sleepBetweenRetries, terraformOptions, testName)
				testWebsite(t, "http", "website_bucket_endpoint", "", 200, "Hello, World!", maxRetries, sleepBetweenRetries, terraformOptions, testName)
				testWebsite(t, "http", "website_bucket_endpoint_path_style", "index.html", 200, "Hello, World!", maxRetries, sleepBetweenRetries, terraformOptions, testName)
				testWebsite(t, "http", "website_domain_name", "not-a-valid-path", 404, "Uh oh", maxRetries, sleepBetweenRetries, terraformOptions, testName)
				testWebsite(t, "http", "redirect_domain_name", "", 200, "Hello, World!", maxRetries, sleepBetweenRetries, terraformOptions, testName)
			})
		})
	}
}
