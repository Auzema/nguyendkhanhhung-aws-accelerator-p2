#!/usr/bin/env bash
# Tear down all lab resources. Errors are ignored (best-effort cleanup).
source "$(dirname "$0")/00-config.sh"
set +e

echo ">> Removing EventBridge target + rule"
aws events remove-targets --rule "$RULE_NAME" --ids "sns-target" --region "$REGION"
aws events delete-rule --name "$RULE_NAME" --region "$REGION"

echo ">> Deleting SNS topic"
aws sns delete-topic --topic-arn "$TOPIC_ARN" --region "$REGION"

echo ">> Emptying + deleting bucket"
aws s3 rm "s3://$BUCKET" --recursive
aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"

echo ">> Cancelling Macie job if still running (completed jobs cannot be cancelled)"
JOB_ID="$(cat "$(dirname "$0")/.last-job-id" 2>/dev/null)"
[ -n "$JOB_ID" ] && aws macie2 update-classification-job \
  --job-id "$JOB_ID" --job-status CANCELLED --region "$REGION"

echo
echo "Optional: stop ALL Macie charges by disabling Macie (deletes findings):"
echo "   aws macie2 disable-macie --region $REGION"
echo "OK teardown done."
