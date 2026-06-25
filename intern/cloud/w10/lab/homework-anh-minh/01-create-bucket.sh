#!/usr/bin/env bash
# Step 1: create a private, encrypted S3 bucket for the sample files.
source "$(dirname "$0")/00-config.sh"

echo ">> Creating bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "   bucket already exists, skipping create"
else
  # us-east-1 must NOT be given a LocationConstraint.
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
fi

echo ">> Blocking all public access"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo ">> Enabling default encryption (SSE-S3)"
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "OK bucket ready: s3://$BUCKET"
