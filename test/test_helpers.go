package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// DOMAIN_NAME_FOR_TEST A Route 53 hosted zone that's available in the Phoenix DevOps AWS account
const DOMAIN_NAME_FOR_TEST = "gruntwork.in"
const HOSTED_ZONE_ID_FOR_TEST = "Z2AJ7S3R6G9UYJ"

// ACM_CERT_DOMAIN_NAME_FOR_TEST An ACM cert provisioned in us-east-1 in the Phoenix DevOps AWS account
const ACM_CERT_DOMAIN_NAME_FOR_TEST = "*.gruntwork.in"

// S3 bucket names can contain only lowercase alphanumeric characters and hyphens
func cleanupNameForS3Bucket(name string) string {
	return strings.ToLower(name)
}

func FormatDomainName(baseName string, uniqueId string) string {
	if baseName == "" {
		return cleanupNameForS3Bucket(fmt.Sprintf("%s.%s", uniqueId, DOMAIN_NAME_FOR_TEST))
	}
	return cleanupNameForS3Bucket(fmt.Sprintf("%s-%s.%s", baseName, uniqueId, DOMAIN_NAME_FOR_TEST))
}

func testWebsite(t *testing.T, protocol string, domainNameOutput string, path string, expectedStatusCode int, expectedBodyText string, maxRetries int, sleepBetweenRetries time.Duration, terratestOptions *terraform.Options, testName string) {
	var domainName string
	if testName == "s3-website-example" {
		domainName = terraform.OutputRequired(t, terratestOptions, domainNameOutput)
	} else {
		domainNameArr := terraform.OutputList(t, terratestOptions, domainNameOutput)
		domainName = domainNameArr[0]
	}

	if domainName == "" {
		t.Fatalf("Output %s was empty", domainNameOutput)
	}

	url := fmt.Sprintf("%s://%s/%s", protocol, domainName, path)
	description := fmt.Sprintf("Making HTTP request to %s", url)

	logger.Log(t, description)

	output := retry.DoWithRetry(t, description, maxRetries, sleepBetweenRetries, func() (string, error) {
		respCode, body := http_helper.HttpGet(t, url, nil)

		if respCode == expectedStatusCode {
			logger.Logf(t, "Got expected status code %d from URL %s", expectedStatusCode, url)
			return body, nil
		}

		return "", fmt.Errorf("Expected status code %d but got %d from URL %s", expectedStatusCode, respCode, url)

	})

	if strings.Contains(output, expectedBodyText) {
		logger.Logf(t, "URL %s contained expected text %s!", url, expectedBodyText)
	} else {
		t.Fatalf("URL %s did not contain expected text %s. Instead, it returned:\n%s", url, expectedBodyText, output)
	}
}
