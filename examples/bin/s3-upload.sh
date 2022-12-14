#!/bin/bash
#
# Copies website contents to S3 Buckets
# Arguments:
#   s3bucketname - Name of S3 Bucket to copy
#
s3bucketname="$1"

if [[ -z "$s3bucketname" ]]; then
  echo "ERROR: No argument supplied"
  echo "Usage: s3-upload.sh <BUCKET_NAME>"
  exit 1
fi

aws s3 sync ../example-website "s3://$s3bucketname" --exclude "README.md"
