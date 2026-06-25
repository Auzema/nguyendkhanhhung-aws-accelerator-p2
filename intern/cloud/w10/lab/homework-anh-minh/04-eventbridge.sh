#!/usr/bin/env bash
# Step 4: enable Macie and route its findings through EventBridge to SNS.
source "$(dirname "$0")/00-config.sh"

echo ">> Enabling Amazon Macie (findings published every 15 min)"
aws macie2 enable-macie --status ENABLED \
  --finding-publishing-frequency FIFTEEN_MINUTES --region "$REGION" 2>/dev/null \
  || aws macie2 update-macie-session --status ENABLED \
       --finding-publishing-frequency FIFTEEN_MINUTES --region "$REGION"

echo ">> Creating EventBridge rule: $RULE_NAME"
aws events put-rule --name "$RULE_NAME" --state ENABLED --region "$REGION" \
  --event-pattern '{"source":["aws.macie"],"detail-type":["Macie Finding"]}'

echo ">> Writing SNS target with an input transformer (readable email)"
TARGETS_FILE="$(dirname "$0")/eventbridge-targets.json"
# Unquoted heredoc: only $TOPIC_ARN expands; \$ keeps the JSONPath literal.
cat > "$TARGETS_FILE" <<EOF
[
  {
    "Id": "sns-target",
    "Arn": "$TOPIC_ARN",
    "InputTransformer": {
      "InputPathsMap": {
        "severity": "\$.detail.severity.description",
        "type": "\$.detail.type",
        "account": "\$.detail.accountId",
        "region": "\$.detail.region",
        "bucket": "\$.detail.resourcesAffected.s3Bucket.name",
        "object": "\$.detail.resourcesAffected.s3Object.key",
        "count": "\$.detail.count",
        "desc": "\$.detail.description"
      },
      "InputTemplate": "\"Amazon Macie sensitive-data finding | Severity: <severity> | Type: <type> | Account: <account> | Region: <region> | Bucket: <bucket> | Object: <object> | Occurrences: <count> | Description: <desc>\""
    }
  }
]
EOF

aws events put-targets --rule "$RULE_NAME" --region "$REGION" \
  --targets "file://$TARGETS_FILE"

echo "OK EventBridge rule wired to SNS topic."
