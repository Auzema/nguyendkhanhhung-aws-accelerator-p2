#!/usr/bin/env bash
# Shared config for the Macie sensitive-data-detection lab.
# Source this from the other scripts:  source ./00-config.sh
set -euo pipefail

export AWS_PAGER=""                       # disable interactive pager
export REGION="us-east-1"
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

export BUCKET="macie-lab-${ACCOUNT_ID}-${REGION}"
export TOPIC_NAME="macie-findings-alerts"
export RULE_NAME="macie-findings-to-sns"
export JOB_NAME="macie-lab-scan"
export EMAIL="lemans19008@gmail.com"

# SNS topic ARN is deterministic from account/region/name.
export TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:${TOPIC_NAME}"
