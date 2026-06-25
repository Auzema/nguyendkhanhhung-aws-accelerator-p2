#!/usr/bin/env bash
# Orchestrate steps 1-5 in order.
set -euo pipefail
DIR="$(dirname "$0")"
source "$DIR/00-config.sh"

bash "$DIR/01-create-bucket.sh"
bash "$DIR/02-samples.sh"
bash "$DIR/03-sns.sh"
bash "$DIR/04-eventbridge.sh"
bash "$DIR/05-run-job.sh"

cat <<EOF

==========================================================
 Setup done. ACTION REQUIRED:
 1. Confirm the SNS subscription email sent to $EMAIL
    (check inbox + spam). Until confirmed, NO alerts arrive.
 2. Wait a few minutes, then run ./06-check.sh to see findings.
 3. When findings publish, EventBridge -> SNS emails you.
 Tear everything down later with ./99-teardown.sh
==========================================================
EOF
