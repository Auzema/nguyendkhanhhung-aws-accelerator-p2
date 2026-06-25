#!/usr/bin/env bash
# Step 6: inspect job status and any findings produced (manual verification).
source "$(dirname "$0")/00-config.sh"

JOB_ID="$(cat "$(dirname "$0")/.last-job-id" 2>/dev/null || true)"
if [ -n "$JOB_ID" ]; then
  echo ">> Job status:"
  aws macie2 describe-classification-job --job-id "$JOB_ID" --region "$REGION" \
    --query '{name:name,state:jobStatus}' --output table
fi

echo ">> Finding IDs:"
IDS="$(aws macie2 list-findings --region "$REGION" --query 'findingIds' --output text)"
if [ -z "$IDS" ]; then
  echo "   no findings yet (job may still be running; re-run in a few minutes)"
  exit 0
fi

echo ">> Finding details:"
aws macie2 get-findings --region "$REGION" --finding-ids $IDS \
  --query 'findings[].{type:type,severity:severity.description,bucket:resourcesAffected.s3Bucket.name,object:resourcesAffected.s3Object.key}' \
  --output table
