#!/usr/bin/env bash
# Step 5: create a ONE_TIME Macie classification job to scan the bucket.
source "$(dirname "$0")/00-config.sh"

STAMP="$(date +%s)"
echo ">> Creating Macie ONE_TIME classification job on s3://$BUCKET"
JOB_ID="$(aws macie2 create-classification-job \
  --region "$REGION" \
  --job-type ONE_TIME \
  --name "${JOB_NAME}-${STAMP}" \
  --client-token "macie-lab-${STAMP}" \
  --s3-job-definition "{\"bucketDefinitions\":[{\"accountId\":\"$ACCOUNT_ID\",\"buckets\":[\"$BUCKET\"]}]}" \
  --query jobId --output text)"

echo "$JOB_ID" > "$(dirname "$0")/.last-job-id"
echo "OK job created: $JOB_ID"
echo ">> Job runs asynchronously (a few minutes)."
echo "   Findings -> EventBridge -> SNS -> email for $EMAIL."
