#!/usr/bin/env bash
# Step 3: create the SNS topic, subscribe the email, and allow EventBridge to publish.
source "$(dirname "$0")/00-config.sh"

echo ">> Creating SNS topic: $TOPIC_NAME"
TOPIC_ARN="$(aws sns create-topic --name "$TOPIC_NAME" --region "$REGION" \
  --query TopicArn --output text)"
echo "   topic arn: $TOPIC_ARN"

echo ">> Subscribing email endpoint: $EMAIL"
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email \
  --notification-endpoint "$EMAIL" --region "$REGION"

echo ">> Setting topic policy so EventBridge can publish to it"
POLICY_FILE="$(dirname "$0")/sns-topic-policy.json"
cat > "$POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgePublish",
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sns:Publish",
      "Resource": "$TOPIC_ARN"
    }
  ]
}
EOF
aws sns set-topic-attributes --topic-arn "$TOPIC_ARN" \
  --attribute-name Policy --attribute-value "file://$POLICY_FILE" --region "$REGION"

echo "OK SNS ready."
echo "!! Open the inbox for $EMAIL and CLICK CONFIRM. No alerts arrive until confirmed."
